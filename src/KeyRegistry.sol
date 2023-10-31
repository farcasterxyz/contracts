// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

import {IKeyRegistry} from "./interfaces/IKeyRegistry.sol";
import {IMetadataValidator} from "./interfaces/IMetadataValidator.sol";
import {IdRegistryLike} from "./interfaces/IdRegistryLike.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Guardians} from "./lib/Guardians.sol";
import {Migration} from "./lib/Migration.sol";
import {Nonces} from "./lib/Nonces.sol";
import {Signatures} from "./lib/Signatures.sol";

/**
 * @title Farcaster KeyRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract KeyRegistry is IKeyRegistry, Guardians, Signatures, EIP712, Nonces, Migration {
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
    address public keyGateway;

    /**
     * @inheritdoc IKeyRegistry
     */
    bool public gatewayFrozen;

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
    ) Guardians(_initialOwner) EIP712("Farcaster KeyRegistry", "1") Migration(24 hours, _initialOwner) {
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
        if (msg.sender != keyGateway) revert Unauthorized();
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
    function bulkAddKeysForMigration(BulkAddData[] calldata items) external migration {
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
    function bulkResetKeysForMigration(BulkResetData[] calldata items) external migration {
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
    function setKeyGateway(address _keyGateway) external onlyOwner {
        if (gatewayFrozen) revert GatewayFrozen();
        emit SetKeyGateway(keyGateway, _keyGateway);
        keyGateway = _keyGateway;
    }

    /**
     * @inheritdoc IKeyRegistry
     */
    function freezeKeyGateway() external onlyOwner {
        if (gatewayFrozen) revert GatewayFrozen();
        emit FreezeKeyGateway(keyGateway);
        gatewayFrozen = true;
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
