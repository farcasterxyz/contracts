// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Nonces} from "openzeppelin-latest/contracts/utils/Nonces.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

import {IdRegistryLike} from "./interfaces/IdRegistryLike.sol";
import {IKeyRegistry} from "./interfaces/IKeyRegistry.sol";
import {IMetadataValidator} from "./interfaces/IMetadataValidator.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Guardians} from "./lib/Guardians.sol";
import {Signatures} from "./lib/Signatures.sol";

/**
 * @title Farcaster KeyRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract KeyRegistry is IKeyRegistry, Guardians, Signatures, EIP712, Nonces {
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

    /// @dev Revert if the owner calls migrateKeys more than once.
    error AlreadyMigrated();

    /// @dev Revert if the owner sets maxKeysPerFid equal to or below its current value.
    error InvalidMaxKeys();

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
     * @param newIdRegistry The new IdRegistry address.
     */
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);

    /**
     * @dev Emit an event when the admin sets a new KeyManager address.
     *
     * @param oldKeyManager The previous KeyManager address.
     * @param newKeyManager The new KeyManager address.
     */
    event SetKeyManager(address oldKeyManager, address newKeyManager);

    /**
     * @dev Emit an event when the admin sets a new maximum keys per fid.
     *
     * @param oldMax The previous maximum.
     * @param newMax The new maximum.
     */
    event SetMaxKeysPerFid(uint256 oldMax, uint256 newMax);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyRegistry
     */
    string public constant VERSION = "2023.10.04";

    /**
     * @inheritdoc IKeyRegistry
     */
    uint24 public constant gracePeriod = uint24(24 hours);

    /**
     * @inheritdoc IKeyRegistry
     */
    bytes32 public constant REMOVE_TYPEHASH =
        keccak256("Remove(address owner,bytes key,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyRegistry
     */
    IdRegistryLike public idRegistry;

    /**
     * @inheritdoc IKeyRegistry
     */
    address public keyManager;

    /**
     * @inheritdoc IKeyRegistry
     */
    uint40 public keysMigratedAt;

    /**
     * @inheritdoc IKeyRegistry
     */
    uint256 public maxKeysPerFid;

    /**
     * @dev Mapping of fid to number of registered keys.
     *
     * @custom:param fid       The fid associated with the keys.
     * @custom:param count     Number of registered keys
     */
    mapping(uint256 fid => uint256 count) public totalKeys;

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
     * @param _idRegistry    IdRegistry contract address.
     * @param _initialOwner  Initial contract owner address.
     * @param _maxKeysPerFid Maximum number of keys per fid.
     */
    constructor(
        address _idRegistry,
        address _initialOwner,
        uint256 _maxKeysPerFid
    ) Guardians(_initialOwner) EIP712("Farcaster KeyRegistry", "1") {
        idRegistry = IdRegistryLike(_idRegistry);
        maxKeysPerFid = _maxKeysPerFid;
        emit SetIdRegistry(address(0), _idRegistry);
        emit SetMaxKeysPerFid(0, _maxKeysPerFid);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyRegistry
     */
    function keyDataOf(uint256 fid, bytes calldata key) external view returns (KeyData memory) {
        return keys[fid][key];
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function isMigrated() public view returns (bool) {
        return keysMigratedAt != 0;
    }

    /*//////////////////////////////////////////////////////////////
                              REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyRegistry
     */
    function add(
        address fidOwner,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata
    ) external {
        if (msg.sender != keyManager) revert Unauthorized();
        _add(_fidOf(fidOwner), keyType, key, metadataType, metadata);
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function remove(bytes calldata key) external {
        _remove(_fidOf(msg.sender), key);
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function removeFor(address fidOwner, bytes calldata key, uint256 deadline, bytes calldata sig) external {
        _verifyRemoveSig(fidOwner, key, deadline, sig);
        _remove(_fidOf(fidOwner), key);
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyRegistry
     */
    function migrateKeys() external onlyOwner {
        if (isMigrated()) revert AlreadyMigrated();
        keysMigratedAt = uint40(block.timestamp);
        emit Migrated(keysMigratedAt);
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function bulkAddKeysForMigration(BulkAddData[] calldata items) external onlyOwner {
        if (isMigrated() && block.timestamp > keysMigratedAt + gracePeriod) {
            revert Unauthorized();
        }

        // Safety: i and j can be incremented unchecked since they are bound by items.length and
        // items[i].keys.length respectively.
        unchecked {
            for (uint256 i = 0; i < items.length; i++) {
                BulkAddData calldata item = items[i];
                for (uint256 j = 0; j < item.keys.length; j++) {
                    _add(item.fid, 1, item.keys[j].key, 1, item.keys[j].metadata, false);
                }
            }
        }
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function bulkResetKeysForMigration(BulkResetData[] calldata items) external onlyOwner {
        if (isMigrated() && block.timestamp > keysMigratedAt + gracePeriod) {
            revert Unauthorized();
        }

        // Safety: i and j can be incremented unchecked since they are bound by items.length and
        // items[i].keys.length respectively.
        unchecked {
            for (uint256 i = 0; i < items.length; i++) {
                BulkResetData calldata item = items[i];
                for (uint256 j = 0; j < item.keys.length; j++) {
                    _reset(item.fid, item.keys[j]);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyRegistry
     */
    function setValidator(uint32 keyType, uint8 metadataType, IMetadataValidator validator) external onlyOwner {
        if (keyType == 0) revert InvalidKeyType();
        if (metadataType == 0) revert InvalidMetadataType();
        emit SetValidator(keyType, metadataType, address(validators[keyType][metadataType]), address(validator));
        validators[keyType][metadataType] = validator;
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function setIdRegistry(address _idRegistry) external onlyOwner {
        emit SetIdRegistry(address(idRegistry), _idRegistry);
        idRegistry = IdRegistryLike(_idRegistry);
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function setKeyManager(address _keyManager) external onlyOwner {
        emit SetKeyManager(keyManager, _keyManager);
        keyManager = _keyManager;
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function setMaxKeysPerFid(uint256 _maxKeysPerFid) external onlyOwner {
        if (_maxKeysPerFid <= maxKeysPerFid) revert InvalidMaxKeys();
        emit SetMaxKeysPerFid(maxKeysPerFid, _maxKeysPerFid);
        maxKeysPerFid = _maxKeysPerFid;
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
        _add(fid, keyType, key, metadataType, metadata, true);
    }

    function _add(
        uint256 fid,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        bool validate
    ) internal whenNotPaused {
        KeyData storage keyData = keys[fid][key];
        if (keyData.state != KeyState.NULL) revert InvalidState();
        if (totalKeys[fid] >= maxKeysPerFid) revert ExceedsMaximum();

        IMetadataValidator validator = validators[keyType][metadataType];
        if (validator == IMetadataValidator(address(0))) {
            revert ValidatorNotFound(keyType, metadataType);
        }

        totalKeys[fid]++;
        keyData.state = KeyState.ADDED;
        keyData.keyType = keyType;
        emit Add(fid, keyType, key, key, metadataType, metadata);

        if (validate) {
            bool isValid = validator.validate(fid, key, metadata);
            if (!isValid) revert InvalidMetadata();
        }
    }

    function _remove(uint256 fid, bytes calldata key) internal whenNotPaused {
        KeyData storage keyData = keys[fid][key];
        if (keyData.state != KeyState.ADDED) revert InvalidState();

        totalKeys[fid]--;
        keyData.state = KeyState.REMOVED;
        emit Remove(fid, key, key);
    }

    function _reset(uint256 fid, bytes calldata key) internal whenNotPaused {
        KeyData storage keyData = keys[fid][key];
        if (keyData.state != KeyState.ADDED) revert InvalidState();

        totalKeys[fid]--;
        keyData.state = KeyState.NULL;
        delete keyData.keyType;
        emit AdminReset(fid, key, key);
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifyRemoveSig(address fidOwner, bytes memory key, uint256 deadline, bytes memory sig) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(abi.encode(REMOVE_TYPEHASH, fidOwner, keccak256(key), _useNonce(fidOwner), deadline))
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
