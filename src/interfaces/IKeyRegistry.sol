// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IMetadataValidator} from "./IMetadataValidator.sol";
import {IdRegistryLike} from "./IdRegistryLike.sol";

interface IKeyRegistry {
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
     * @param keys Metadata metadata of the signer key.
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
     * @notice Period in seconds after migration during which admin can bulk add/reset keys.
     *         Admins can make corrections to the migrated data during the grace period if necessary,
     *         but cannot make changes after it expires.
     */
    function gracePeriod() external view returns (uint24);

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
     * @notice Timestamp at which keys migrated. Hubs will cut over to use this KeyRegistry as their
     *         source of truth after this timestamp.
     */
    function keysMigratedAt() external view returns (uint40);

    /**
     * @notice Maximum number of keys per fid.
     */
    function maxKeysPerFid() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieve state and type data for a given key.
     *
     * @param fid   The fid associated with the key.
     * @param key   Bytes of the key.
     *
     * @return KeyData struct that contains the state and keyType.
     */
    function keyDataOf(uint256 fid, bytes calldata key) external view returns (KeyData memory);

    /**
     * @notice Check if the contract has been migrated.
     *
     * @return true if the contract has been migrated, false otherwise.
     */
    function isMigrated() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              REMOVE KEYS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Remove a key associated with the caller's fid, setting the key state to REMOVED.
     *         The key must be in the ADDED state.
     *
     * @param key   Bytes of the key to remove.
     */
    function remove(bytes calldata key) external;

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
     * @notice Set the time of the key migration and emit an event. Hubs will watch this event and
     *         cut over to use the onchain registry as their source of truth after this timestamp.
     *         Only callable by the contract owner.
     */
    function migrateKeys() external;

    /**
     * @notice Add multiple keys as part of the initial migration. Only callable by the contract owner.
     *
     * @param items An array of BulkAddData structs including fid and array of BulkAddKey structs.
     */
    function bulkAddKeysForMigration(BulkAddData[] calldata items) external;

    /**
     * @notice Reset multiple keys as part of the initial migration. Only callable by the contract owner.
     *         Reset is not the same as removal: this function sets the key state back to NULL,
     *         rather than REMOVED. This allows the owner to correct any errors in the initial migration until
     *         the grace period expires.
     *
     * @param items    A list of BulkResetData structs including an fid and array of keys.
     */
    function bulkResetKeysForMigration(BulkResetData[] calldata items) external;

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
    function setIdRegistry(address _idRegistry) external;

    /**
     * @notice Set the KeyGateway address allowed to add keys. Only callable by owner.
     *
     * @param _keyGateway The new KeyGateway address.
     */
    function setKeyGateway(address _keyGateway) external;

    /**
     * @notice Set the maximum number of keys allowed per fid. Only callable by owner.
     *
     * @param _maxKeysPerFid The new max keys per fid.
     */
    function setMaxKeysPerFid(uint256 _maxKeysPerFid) external;
}
