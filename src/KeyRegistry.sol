// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "openzeppelin-latest/contracts/utils/Nonces.sol";

import {IdRegistryLike} from "./interfaces/IdRegistryLike.sol";
import {IMetadataValidator} from "./interfaces/IMetadataValidator.sol";
import {IdRegistry} from "./IdRegistry.sol";
import {Signatures} from "./lib/Signatures.sol";
import {TrustedCaller} from "./lib/TrustedCaller.sol";

/**
 * @title KeyRegistry
 *
 * @notice See ../docs/docs.md for an overview.
 */

contract KeyRegistry is TrustedCaller, Signatures, EIP712, Nonces {
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

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if a key violates KeyState transition rules.
    error InvalidState();

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

    /// @dev Revert if the owner calls migrateKeys more than once.
    error AlreadyMigrated();

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
     * @dev Emit an event when the admin calls migrateKeys. Used to migrate Hubs from using
     *      offchain signers to onchain signers.
     *
     *      Hubs listen for this and:
     *      1. Stop accepting Farcaster Signer messages with a timestamp >= keysMigratedAt.
     *      2. After the grace period (24 hours), stop accepting all Farcaster Signer messages.
     *      3. Drop any messages created by off-chain Farcaster Signers whose pub key was
     *         not emitted as an Add event.
     *
     *      If SignerMessages are not correctly migrated by an admin during the migration,
     *      there is a chance that there is some data loss, which is considered an acceptable
     *      risk for this migration.
     *
     *      If this event is emitted incorrectly ahead of schedule, new users cannot not post
     *      and existing users cannot add new apps. A protocol upgrade will be necessary
     *      which could take up to 6 weeks to roll out correctly.
     *
     * @param keysMigratedAt  The timestamp at which the migration occurred.
     */
    event Migrated(uint256 indexed keysMigratedAt);

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
     * @param newIdRegistry The ne IdRegistry address.
     */
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant _ADD_TYPEHASH = keccak256(
        "Add(address owner,uint32 keyType,bytes key,uint8 metadataType,bytes metadata,uint256 nonce,uint256 deadline)"
    );

    bytes32 internal constant _REMOVE_TYPEHASH =
        keccak256("Remove(address owner,bytes key,uint256 nonce,uint256 deadline)");

    /**
     * @dev Period in seconds after migration during which admin can bulk add/reset keys.
     *      Admins can make corrections to the migrated data during the grace period if necessary,
     *      but cannot make changes after it expires.
     */
    uint24 public constant gracePeriod = uint24(24 hours);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The IdRegistry contract.
     */
    IdRegistryLike public idRegistry;

    /**
     * @dev Timestamp at which keys migrated. Hubs will cut over to use this KeyRegistry as their
     *      source of truth after this timestamp.
     */
    uint40 public keysMigratedAt;

    /**
     * @dev Mapping of fid to a key to the key's data.
     *
     * @custom:param fid       The fid associated with the key.
     * @custom:param key       Bytes of the key.
     * @custom:param data      Struct with the state and key type. In the initial migration
     *                         all keys will have data.keyType == 1.
     */
    mapping(uint256 fid => mapping(bytes key => KeyData data)) public keys;

    /**
     * @dev Mapping of keyType to metadataType to validator contract.
     *
     * @custom:param keyType      Numeric keyType.
     * @custom:param metadataType Metadata metadataType.
     * @custom:param validator    Validator contract implementing IMetadataValidator.
     */
    mapping(uint32 keyType => mapping(uint8 metadataType => IMetadataValidator validator)) public validators;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the IdRegistry and owner.
     *
     * @param _idRegistry   IdRegistry contract address.
     * @param _initialOwner Initial contract owner address.
     */
    constructor(
        address _idRegistry,
        address _initialOwner
    ) TrustedCaller(_initialOwner) EIP712("Farcaster KeyRegistry", "1") {
        idRegistry = IdRegistryLike(_idRegistry);
    }

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
    function keyDataOf(uint256 fid, bytes calldata key) external view returns (KeyData memory) {
        return keys[fid][key];
    }

    /**
     * @notice Check if the contract has been migrated.
     *
     * @return true if the contract has been migrated, false otherwise.
     */
    function isMigrated() public view returns (bool) {
        return keysMigratedAt != 0;
    }

    /*//////////////////////////////////////////////////////////////
                              REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a key to the caller's fid, setting the key state to ADDED.
     *
     * @param keyType      The key's numeric keyType.
     * @param key          Bytes of the key to add.
     * @param metadataType Metadata type ID.
     * @param metadata     Metadata about the key, which is not stored and only emitted in an event.
     */
    function add(uint32 keyType, bytes calldata key, uint8 metadataType, bytes calldata metadata) external {
        _add(_fidOf(msg.sender), keyType, key, metadataType, metadata);
    }

    /**
     * @notice Add a key on behalf of another fid owner, setting the key state to ADDED.
     *         caller must supply a valid EIP-712 Add signature from the fid owner.
     *
     * @param fidOwner     The fid owner address.
     * @param keyType      The key's numeric keyType.
     * @param key          Bytes of the key to add.
     * @param metadataType Metadata type ID.
     * @param metadata     Metadata about the key, which is not stored and only emitted in an event.
     * @param deadline     Deadline after which the signature expires.
     * @param sig          EIP-712 Add signature generated by fid owner.
     */
    function addFor(
        address fidOwner,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint256 deadline,
        bytes calldata sig
    ) external {
        _verifyAddSig(fidOwner, keyType, key, metadataType, metadata, deadline, sig);
        _add(_fidOf(fidOwner), keyType, key, metadataType, metadata);
    }

    /**
     * @notice Add a key on behalf of another fid owner, setting the key state to ADDED.
     *         Can only be called by the trustedCaller.
     *
     * @param fidOwner     The fid owner address.
     * @param keyType      The key's numeric keyType.
     * @param key          Bytes of the key to add.
     * @param metadataType Metadata type ID.
     * @param metadata     Metadata about the key, which is not stored and only emitted in an event.
     */
    function trustedAdd(
        address fidOwner,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata
    ) external onlyTrustedCaller {
        _add(_fidOf(fidOwner), keyType, key, metadataType, metadata);
    }

    /**
     * @notice Remove a key associated with the caller's fid, setting the key state to REMOVED.
     *         The key must be in the ADDED state.
     *
     * @param key   Bytes of the key to remove.
     */
    function remove(bytes calldata key) external {
        _remove(_fidOf(msg.sender), key);
    }

    /**
     * @notice Remove a key on behalf of another fid owner, setting the key state to REMOVED.
     *         caller must supply a valid EIP-712 Remove signature from the fid owner.
     *
     * @param fidOwner The fid owner address.
     * @param key      Bytes of the key to remove.
     * @param deadline Deadline after which the signature expires.
     * @param sig      EIP-712 Remove signature generated by fid owner.
     */
    function removeFor(address fidOwner, bytes calldata key, uint256 deadline, bytes calldata sig) external {
        _verifyRemoveSig(fidOwner, key, deadline, sig);
        _remove(_fidOf(fidOwner), key);
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    struct BulkAddData {
        uint256 fid;
        BulkAddKey[] keys;
    }

    struct BulkAddKey {
        bytes key;
        bytes metadata;
    }

    struct BulkResetData {
        uint256 fid;
        bytes[] keys;
    }

    /**
     * @notice Set the time of the key migration and emit an event. Hubs will watch this event and
     *         cut over to use the onchain registry as their source of truth after this timestamp.
     *         Only callable by the contract owner.
     */
    function migrateKeys() external onlyOwner {
        if (isMigrated()) revert AlreadyMigrated();
        keysMigratedAt = uint40(block.timestamp);
        emit Migrated(keysMigratedAt);
    }

    /**
     * @notice Add multiple keys as part of the initial migration. Only callable by the contract owner.
     *
     * @param items An array of BulkAddData structs including fid and array of BulkAddKey structs.
     */
    function bulkAddKeysForMigration(BulkAddData[] calldata items) external onlyOwner {
        if (isMigrated() && block.timestamp > keysMigratedAt + gracePeriod) {
            revert Unauthorized();
        }

        // Safety: i and j can be incremented unchecked since they are bound by items.length and
        // item[i].keys.length respectively.
        unchecked {
            for (uint256 i = 0; i < items.length; i++) {
                BulkAddData calldata item = items[i];
                for (uint256 j = 0; j < item.keys.length; j++) {
                    // TODO: add note about griefing during migration
                    _add(item.fid, 1, item.keys[j].key, 1, item.keys[j].metadata);
                }
            }
        }
    }

    /**
     * @notice Reset multiple keys as part of the initial migration. Only callable by the contract owner.
     *         Reset is not the same as removal: this function sets the key state back to NULL,
     *         rather than REMOVED. This allows the owner to correct any errors in the initial migration until
     *         the grace period expires.
     *
     * @param items    A list of BulkResetData structs including an fid and array of keys.
     */
    function bulkResetKeysForMigration(BulkResetData[] calldata items) external onlyOwner {
        if (isMigrated() && block.timestamp > keysMigratedAt + gracePeriod) {
            revert Unauthorized();
        }

        // Safety: i and j can be incremented unchecked since they are bound by items.length and
        // fidKeys[i].length respectively.
        unchecked {
            for (uint256 i = 0; i < items.length; i++) {
                BulkResetData calldata item = items[i];
                for (uint256 j = 0; j < item.keys.length; j++) {
                    // TODO: add note about griefing during migration
                    _reset(item.fid, item.keys[j]);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set a metadata validator contract for the given keyType and metadataType. Only callable by owner.
     *
     * @param keyType      The numeric key type ID associated with this validator.
     * @param metadataType The numeric metadata type ID associated with this validator.
     * @param validator    Contract implementing IMetadataValidator.
     */
    function setValidator(uint32 keyType, uint8 metadataType, IMetadataValidator validator) external onlyOwner {
        if (keyType == 0) revert InvalidKeyType();
        if (metadataType == 0) revert InvalidMetadataType();
        emit SetValidator(keyType, metadataType, address(validators[keyType][metadataType]), address(validator));
        validators[keyType][metadataType] = validator;
    }

    /**
     * @notice Set the IdRegistry contract address. Only callable by owner.
     *
     * @param _idRegistry The new IdRegistry address.
     */
    function setIdRegistry(address _idRegistry) external onlyOwner {
        emit SetIdRegistry(address(idRegistry), _idRegistry);
        idRegistry = IdRegistryLike(_idRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _add(
        uint256 fid,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata
    ) internal {
        KeyData storage keyData = keys[fid][key];
        if (keyData.state != KeyState.NULL) revert InvalidState();

        IMetadataValidator validator = validators[keyType][metadataType];
        if (validator == IMetadataValidator(address(0))) {
            revert ValidatorNotFound(keyType, metadataType);
        }
        bool isValid = validator.validate(fid, key, metadata);
        if (!isValid) revert InvalidMetadata();

        keyData.state = KeyState.ADDED;
        keyData.keyType = keyType;
        emit Add(fid, keyType, key, key, metadataType, metadata);
    }

    function _remove(uint256 fid, bytes calldata key) internal {
        KeyData storage keyData = keys[fid][key];
        if (keyData.state != KeyState.ADDED) revert InvalidState();

        keyData.state = KeyState.REMOVED;
        emit Remove(fid, key, key);
    }

    function _reset(uint256 fid, bytes calldata key) internal {
        KeyData storage keyData = keys[fid][key];
        if (keyData.state != KeyState.ADDED) revert InvalidState();

        keyData.state = KeyState.NULL;
        delete keyData.keyType;
        emit AdminReset(fid, key, key);
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifyAddSig(
        address fidOwner,
        uint32 keyType,
        bytes memory key,
        uint8 metadataType,
        bytes memory metadata,
        uint256 deadline,
        bytes memory sig
    ) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _ADD_TYPEHASH,
                        fidOwner,
                        keyType,
                        keccak256(key),
                        metadataType,
                        keccak256(metadata),
                        _useNonce(fidOwner),
                        deadline
                    )
                )
            ),
            fidOwner,
            deadline,
            sig
        );
    }

    function _verifyRemoveSig(address fidOwner, bytes memory key, uint256 deadline, bytes memory sig) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(abi.encode(_REMOVE_TYPEHASH, fidOwner, keccak256(key), _useNonce(fidOwner), deadline))
            ),
            fidOwner,
            deadline,
            sig
        );
    }

    /*//////////////////////////////////////////////////////////////
                           FID HELPERS 
    //////////////////////////////////////////////////////////////*/

    function _fidOf(address fidOwner) internal view returns (uint256 fid) {
        fid = idRegistry.idOf(fidOwner);
        if (fid == 0) revert Unauthorized();
    }
}
