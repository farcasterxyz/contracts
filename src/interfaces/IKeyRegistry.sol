// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IMetadataValidator} from "./IMetadataValidator.sol";
import {IdRegistryLike} from "./IdRegistryLike.sol";

interface IKeyRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if a key violates KeyState transition rules.
    error InvalidState();

    /// @dev Revert if adding a key exceeds the maximum number of allowed keys per fid.
    error ExceedsMaximum();

    /// @dev Revert if a validator has not been registered for this keyType and metadataType.
    error ValidatorNotFound(uint32 keyType, uint8 metadataType);

    /// @dev Revert if metadata validation failed.
    error InvalidMetadata();

    /// @dev Revert if the admin sets a validator for keyType 0.
    error InvalidKeyType();

    /// @dev Revert if the admin sets a validator for metadataType 0.
    error InvalidMetadataType();

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

    /// @dev Revert if the owner sets maxKeysPerFid equal to or below its current value.
    error InvalidMaxKeys();

    /// @dev Revert when the gateway dependency is permanently frozen.
    error GatewayFrozen();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when an admin or fid adds a new key.
     *
     *      Hubs listen for this, validate that keyBytes is an EdDSA pub key and keyType == 1 and
     *      add keyBytes to its SignerStore. Messages signed by keyBytes with `fid` are now valid
     *      and accepted over gossip, sync and client apis. Hubs assume the invariants:
     *
     *      1. Add(fid, ..., key, keyBytes, ...) cannot emit if there is an earlier emit with
     *         Add(fid, ..., key, keyBytes, ...) and no AdminReset(fid, key, keyBytes) inbetween.
     *
     *      2. Add(fid, ..., key, keyBytes, ...) cannot emit if there is an earlier emit with
     *         Remove(fid, key, keyBytes).
     *
     *      3. For all Add(..., ..., key, keyBytes, ...), key = keccak(keyBytes)
     *
     * @param fid          The fid associated with the key.
     * @param keyType      The type of the key.
     * @param key          The key being registered. (indexed as hash)
     * @param keyBytes     The bytes of the key being registered.
     * @param metadataType The type of the metadata.
     * @param metadata     Metadata about the key.
     */
    event Add(
        uint256 indexed fid,
        uint32 indexed keyType,
        bytes indexed key,
        bytes keyBytes,
        uint8 metadataType,
        bytes metadata
    );

    /**
     * @dev Emit an event when an fid removes an added key.
     *
     *      Hubs listen for this, validate that keyType == 1 and keyBytes exists in its SignerStore.
     *      keyBytes is marked as removed, messages signed by keyBytes with `fid` are invalid,
     *      dropped immediately and no longer accepted. Hubs assume the invariants:
     *
     *      1. Remove(fid, key, keyBytes) cannot emit if there is no earlier emit with
     *         Add(fid, ..., key, keyBytes, ...)
     *
     *      2. Remove(fid, key, keyBytes) cannot emit if there is an earlier emit with
     *         Remove(fid, key, keyBytes)
     *
     *      3. For all Remove(..., key, keyBytes), key = keccak(keyBytes)
     *
     * @param fid       The fid associated with the key.
     * @param key       The key being registered. (indexed as hash)
     * @param keyBytes  The bytes of the key being registered.
     */
    event Remove(uint256 indexed fid, bytes indexed key, bytes keyBytes);

    /**
     * @dev Emit an event when an admin resets an added key.
     *
     *      Hubs listen for this, validate that keyType == 1 and that keyBytes exists in its SignerStore.
     *      keyBytes is no longer tracked, messages signed by keyBytes with `fid` are invalid, dropped
     *      immediately and not accepted. Hubs assume the following invariants:
     *
     *      1. AdminReset(fid, key, keyBytes) cannot emit unless the most recent event for the fid
     *         was Add(fid, ..., key, keyBytes, ...).
     *
     *      2. For all AdminReset(..., key, keyBytes), key = keccak(keyBytes).
     *
     *      3. AdminReset() cannot emit after Migrated().
     *
     * @param fid       The fid associated with the key.
     * @param key       The key being reset. (indexed as hash)
     * @param keyBytes  The bytes of the key being registered.
     */
    event AdminReset(uint256 indexed fid, bytes indexed key, bytes keyBytes);

    /**
     * @dev Emit an event when the admin sets a metadata validator contract for a given
     *      keyType and metadataType.
     *
     * @param keyType      The numeric keyType associated with this validator.
     * @param metadataType The metadataType associated with this validator.
     * @param oldValidator The previous validator contract address.
     * @param newValidator The new validator contract address.
     */
    event SetValidator(uint32 keyType, uint8 metadataType, address oldValidator, address newValidator);

    /**
     * @dev Emit an event when the admin sets a new IdRegistry contract address.
     *
     * @param oldIdRegistry The previous IdRegistry address.
     * @param newIdRegistry The new IdRegistry address.
     */
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);

    /**
     * @dev Emit an event when the admin sets a new KeyGateway address.
     *
     * @param oldKeyGateway The previous KeyGateway address.
     * @param newKeyGateway The new KeyGateway address.
     */
    event SetKeyGateway(address oldKeyGateway, address newKeyGateway);

    /**
     * @dev Emit an event when the admin sets a new maximum keys per fid.
     *
     * @param oldMax The previous maximum.
     * @param newMax The new maximum.
     */
    event SetMaxKeysPerFid(uint256 oldMax, uint256 newMax);

    /**
     * @dev Emit an event when the contract owner permanently freezes the KeyGateway address.
     *
     * @param keyGateway The permanent KeyGateway address.
     */
    event FreezeKeyGateway(address keyGateway);

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice State enumeration for a key in the registry. During migration, an admin can change
     *          the state of any fids key from NULL to ADDED or ADDED to NULL. After migration, an
     *          fid can change the state of a key from NULL to ADDED or ADDED to REMOVED only.
     *
     *          - NULL: The key is not in the registry.
     *          - ADDED: The key has been added to the registry.
     *          - REMOVED: The key was added to the registry but is now removed.
     */
    enum KeyState {
        NULL,
        ADDED,
        REMOVED
    }

    /**
     *  @notice Data about a key.
     *
     *  @param state   The current state of the key.
     *  @param keyType Numeric ID representing the manner in which the key should be used.
     */
    struct KeyData {
        KeyState state;
        uint32 keyType;
    }

    /**
     * @dev Struct argument for bulk add function, representing an FID
     *      and its associated keys.
     *
     * @param fid  Fid associated with provided keys to add.
     * @param keys Array of BulkAddKey structs, including key and metadata.
     */
    struct BulkAddData {
        uint256 fid;
        BulkAddKey[] keys;
    }

    /**
     * @dev Struct argument for bulk add function, representing a key
     *      and its associated metadata.
     *
     * @param key  Bytes of the signer key.
     * @param metadata Metadata of the signer key.
     */
    struct BulkAddKey {
        bytes key;
        bytes metadata;
    }

    /**
     * @dev Struct argument for bulk reset function, representing an FID
     *      and its associated keys.
     *
     * @param fid  Fid associated with provided keys to reset.
     * @param keys Array of keys to reset.
     */
    struct BulkResetData {
        uint256 fid;
        bytes[] keys;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice EIP-712 typehash for Remove signatures.
     */
    function REMOVE_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The IdRegistry contract.
     */
    function idRegistry() external view returns (IdRegistryLike);

    /**
     * @notice The KeyGateway address.
     */
    function keyGateway() external view returns (address);

    /**
     * @notice Whether the KeyGateway address is permanently frozen.
     */
    function gatewayFrozen() external view returns (bool);

    /**
     * @notice Maximum number of keys per fid.
     */
    function maxKeysPerFid() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Return number of active keys for a given fid.
     *
     * @param fid the fid associated with the keys.
     *
     * @return uint256 total number of active keys associated with the fid.
     */
    function totalKeys(uint256 fid, KeyState state) external view returns (uint256);

    /**
     * @notice Return key at the given index in the fid's key set. Can be
     *         called to enumerate all active keys for a given fid.
     *
     * @param fid   the fid associated with the key.
     * @param index index of the key in the fid's key set. Must be a value
     *              less than totalKeys(fid). Note that because keys are
     *              stored in an underlying enumerable set, the ordering of
     *              keys is not guaranteed to be stable.
     *
     * @return bytes Bytes of the key.
     */
    function keyAt(uint256 fid, KeyState state, uint256 index) external view returns (bytes memory);

    /**
     * @notice Return an array of all active keys for a given fid.
     * @dev    WARNING: This function will copy the entire key set to memory,
     *         which can be quite expensive. This is intended to be called
     *         offchain with eth_call, not onchain.
     *
     * @param fid the fid associated with the keys.
     *
     * @return bytes[] Array of all keys.
     */
    function keysOf(uint256 fid, KeyState state) external view returns (bytes[] memory);

    /**
     * @notice Return an array of all active keys for a given fid,
     *         paged by index and batch size.
     *
     * @param fid       The fid associated with the keys.
     * @param startIdx  Start index of lookup.
     * @param batchSize Number of items to return.
     *
     * @return page    Array of keys.
     * @return nextIdx Next index in the set of all keys.
     */
    function keysOf(
        uint256 fid,
        KeyState state,
        uint256 startIdx,
        uint256 batchSize
    ) external view returns (bytes[] memory page, uint256 nextIdx);

    /**
     * @notice Retrieve state and type data for a given key.
     *
     * @param fid   The fid associated with the key.
     * @param key   Bytes of the key.
     *
     * @return KeyData struct that contains the state and keyType.
     */
    function keyDataOf(uint256 fid, bytes calldata key) external view returns (KeyData memory);

    /*//////////////////////////////////////////////////////////////
                              REMOVE KEYS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Remove a key associated with the caller's fid, setting the key state to REMOVED.
     *         The key must be in the ADDED state.
     *
     * @param key   Bytes of the key to remove.
     */
    function remove(
        bytes calldata key
    ) external;

    /**
     * @notice Remove a key on behalf of another fid owner, setting the key state to REMOVED.
     *         caller must supply a valid EIP-712 Remove signature from the fid owner.
     *
     * @param fidOwner The fid owner address.
     * @param key      Bytes of the key to remove.
     * @param deadline Deadline after which the signature expires.
     * @param sig      EIP-712 Remove signature generated by fid owner.
     */
    function removeFor(address fidOwner, bytes calldata key, uint256 deadline, bytes calldata sig) external;

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a key associated with fidOwner's fid, setting the key state to ADDED.
     *         Can only be called by the keyGateway address.
     *
     * @param keyType      The key's numeric keyType.
     * @param key          Bytes of the key to add.
     * @param metadataType Metadata type ID.
     * @param metadata     Metadata about the key, which is not stored and only emitted in an event.
     */
    function add(
        address fidOwner,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata
    ) external;

    /**
     * @notice Add multiple keys as part of the initial migration. Only callable by the contract owner.
     *
     * @param items An array of BulkAddData structs including fid and array of BulkAddKey structs.
     */
    function bulkAddKeysForMigration(
        BulkAddData[] calldata items
    ) external;

    /**
     * @notice Reset multiple keys as part of the initial migration. Only callable by the contract owner.
     *         Reset is not the same as removal: this function sets the key state back to NULL,
     *         rather than REMOVED. This allows the owner to correct any errors in the initial migration until
     *         the grace period expires.
     *
     * @param items   A list of BulkResetData structs including an fid and array of keys.
     */
    function bulkResetKeysForMigration(
        BulkResetData[] calldata items
    ) external;

    /**
     * @notice Set a metadata validator contract for the given keyType and metadataType. Only callable by owner.
     *
     * @param keyType      The numeric key type ID associated with this validator.
     * @param metadataType The numeric metadata type ID associated with this validator.
     * @param validator    Contract implementing IMetadataValidator.
     */
    function setValidator(uint32 keyType, uint8 metadataType, IMetadataValidator validator) external;

    /**
     * @notice Set the IdRegistry contract address. Only callable by owner.
     *
     * @param _idRegistry The new IdRegistry address.
     */
    function setIdRegistry(
        address _idRegistry
    ) external;

    /**
     * @notice Set the KeyGateway address allowed to add keys. Only callable by owner.
     *
     * @param _keyGateway The new KeyGateway address.
     */
    function setKeyGateway(
        address _keyGateway
    ) external;

    /**
     * @notice Permanently freeze the KeyGateway address. Only callable by owner.
     */
    function freezeKeyGateway() external;

    /**
     * @notice Set the maximum number of keys allowed per fid. Only callable by owner.
     *
     * @param _maxKeysPerFid The new max keys per fid.
     */
    function setMaxKeysPerFid(
        uint256 _maxKeysPerFid
    ) external;
}
