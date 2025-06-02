// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {EIP712} from "./abstract/EIP712.sol";
import {Nonces} from "./abstract/Nonces.sol";
import {Signatures} from "./abstract/Signatures.sol";
import {Migration} from "./abstract/Migration.sol";

/**
 * @title Farcaster IdRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract IdRegistry is IIdRegistry, Migration, Signatures, EIP712, Nonces {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    string public constant name = "Farcaster FID";

    /**
     * @inheritdoc IIdRegistry
     */
    string public constant VERSION = "2023.11.15";

    /**
     * @inheritdoc IIdRegistry
     */
    bytes32 public constant TRANSFER_TYPEHASH =
        keccak256("Transfer(uint256 fid,address to,uint256 nonce,uint256 deadline)");

    /**
     * @inheritdoc IIdRegistry
     */
    bytes32 public constant TRANSFER_AND_CHANGE_RECOVERY_TYPEHASH =
        keccak256("TransferAndChangeRecovery(uint256 fid,address to,address recovery,uint256 nonce,uint256 deadline)");

    /**
     * @inheritdoc IIdRegistry
     */
    bytes32 public constant CHANGE_RECOVERY_ADDRESS_TYPEHASH =
        keccak256("ChangeRecoveryAddress(uint256 fid,address from,address to,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    address public idGateway;

    /**
     * @inheritdoc IIdRegistry
     */
    bool public gatewayFrozen;

    /**
     * @inheritdoc IIdRegistry
     */
    uint256 public idCounter;

    /**
     * @inheritdoc IIdRegistry
     */
    mapping(address owner => uint256 fid) public idOf;

    /**
     * @inheritdoc IIdRegistry
     */
    mapping(uint256 fid => address custody) public custodyOf;

    /**
     * @inheritdoc IIdRegistry
     */
    mapping(uint256 fid => address recovery) public recoveryOf;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the owner of the contract to the provided _owner.
     *
     * @param _migrator     Migrator address.
     * @param _initialOwner Initial owner address.
     *
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(
        address _migrator,
        address _initialOwner
    ) Migration(24 hours, _migrator, _initialOwner) EIP712("Farcaster IdRegistry", "1") {}

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    function register(address to, address recovery) external whenNotPaused returns (uint256 fid) {
        if (msg.sender != idGateway) revert Unauthorized();

        /* Revert if the target(to) has an fid */
        if (idOf[to] != 0) revert HasId();

        /* Safety: idCounter won't realistically overflow. */
        unchecked {
            /* Incrementing before assignment ensures that no one gets the 0 fid. */
            fid = ++idCounter;
        }

        _unsafeRegister(fid, to, recovery);
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    function transfer(address to, uint256 deadline, bytes calldata sig) external {
        uint256 fromId = _validateTransfer(msg.sender, to);

        /* Revert if signature is invalid */
        _verifyTransferSig({fid: fromId, to: to, deadline: deadline, signer: to, sig: sig});

        _unsafeTransfer(fromId, msg.sender, to);
    }

    /**
     * @inheritdoc IIdRegistry
     */
    function transferFor(
        address from,
        address to,
        uint256 fromDeadline,
        bytes calldata fromSig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external {
        uint256 fromId = _validateTransfer(from, to);

        /* Revert if either signature is invalid */
        _verifyTransferSig({fid: fromId, to: to, deadline: fromDeadline, signer: from, sig: fromSig});
        _verifyTransferSig({fid: fromId, to: to, deadline: toDeadline, signer: to, sig: toSig});

        _unsafeTransfer(fromId, from, to);
    }

    /**
     * @inheritdoc IIdRegistry
     */
    function transferAndChangeRecovery(address to, address recovery, uint256 deadline, bytes calldata sig) external {
        uint256 fromId = _validateTransfer(msg.sender, to);

        /* Revert if signature is invalid */
        _verifyTransferAndChangeRecoverySig({
            fid: fromId,
            to: to,
            recovery: recovery,
            deadline: deadline,
            signer: to,
            sig: sig
        });

        _unsafeTransfer(fromId, msg.sender, to);
        _unsafeChangeRecovery(fromId, recovery);
    }

    /**
     * @inheritdoc IIdRegistry
     */
    function transferAndChangeRecoveryFor(
        address from,
        address to,
        address recovery,
        uint256 fromDeadline,
        bytes calldata fromSig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external {
        uint256 fromId = _validateTransfer(from, to);

        /* Revert if either signature is invalid */
        _verifyTransferAndChangeRecoverySig({
            fid: fromId,
            to: to,
            recovery: recovery,
            deadline: fromDeadline,
            signer: from,
            sig: fromSig
        });
        _verifyTransferAndChangeRecoverySig({
            fid: fromId,
            to: to,
            recovery: recovery,
            deadline: toDeadline,
            signer: to,
            sig: toSig
        });

        _unsafeTransfer(fromId, from, to);
        _unsafeChangeRecovery(fromId, recovery);
    }

    /**
     * @dev Retrieve fid and validate sender/recipient
     */
    function _validateTransfer(address from, address to) internal view returns (uint256 fromId) {
        fromId = idOf[from];

        /* Revert if the sender has no id */
        if (fromId == 0) revert HasNoId();
        /* Revert if recipient has an id */
        if (idOf[to] != 0) revert HasId();
    }

    /**
     * @dev Register the fid without checking invariants.
     */
    function _unsafeRegister(uint256 id, address to, address recovery) internal {
        idOf[to] = id;
        custodyOf[id] = to;
        recoveryOf[id] = recovery;

        emit Register(to, id, recovery);
    }

    /**
     * @dev Transfer the fid to another address without checking invariants.
     */
    function _unsafeTransfer(uint256 id, address from, address to) internal whenNotPaused {
        idOf[to] = id;
        custodyOf[id] = to;
        delete idOf[from];

        emit Transfer(from, to, id);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    function changeRecoveryAddress(
        address recovery
    ) external whenNotPaused {
        /* Revert if the caller does not own an fid */
        uint256 ownerId = idOf[msg.sender];
        if (ownerId == 0) revert HasNoId();

        _unsafeChangeRecovery(ownerId, recovery);
    }

    /**
     * @inheritdoc IIdRegistry
     */
    function changeRecoveryAddressFor(
        address owner,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external whenNotPaused {
        /* Revert if the caller does not own an fid */
        uint256 ownerId = idOf[owner];
        if (ownerId == 0) revert HasNoId();

        _verifyChangeRecoveryAddressSig({
            fid: ownerId,
            from: recoveryOf[ownerId],
            to: recovery,
            deadline: deadline,
            signer: owner,
            sig: sig
        });

        _unsafeChangeRecovery(ownerId, recovery);
    }

    /**
     * @dev Change recovery address without checking invariants.
     */
    function _unsafeChangeRecovery(uint256 id, address recovery) internal whenNotPaused {
        /* Change the recovery address */
        recoveryOf[id] = recovery;

        emit ChangeRecoveryAddress(id, recovery);
    }

    /**
     * @inheritdoc IIdRegistry
     */
    function recover(address from, address to, uint256 deadline, bytes calldata sig) external {
        /* Revert if from does not own an fid */
        uint256 fromId = idOf[from];
        if (fromId == 0) revert HasNoId();

        /* Revert if the caller is not the recovery address */
        address caller = msg.sender;
        if (recoveryOf[fromId] != caller) revert Unauthorized();

        /* Revert if destination(to) already has an fid */
        if (idOf[to] != 0) revert HasId();

        /* Revert if signature is invalid */
        _verifyTransferSig({fid: fromId, to: to, deadline: deadline, signer: to, sig: sig});

        emit Recover(from, to, fromId);
        _unsafeTransfer(fromId, from, to);
    }

    /**
     * @inheritdoc IIdRegistry
     */
    function recoverFor(
        address from,
        address to,
        uint256 recoveryDeadline,
        bytes calldata recoverySig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external {
        /* Revert if from does not own an fid */
        uint256 fromId = idOf[from];
        if (fromId == 0) revert HasNoId();

        /* Revert if destination(to) already has an fid */
        if (idOf[to] != 0) revert HasId();

        /* Revert if either signature is invalid */
        _verifyTransferSig({
            fid: fromId,
            to: to,
            deadline: recoveryDeadline,
            signer: recoveryOf[fromId],
            sig: recoverySig
        });
        _verifyTransferSig({fid: fromId, to: to, deadline: toDeadline, signer: to, sig: toSig});

        emit Recover(from, to, fromId);
        _unsafeTransfer(fromId, from, to);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    function setIdGateway(
        address _idGateway
    ) external onlyOwner {
        if (gatewayFrozen) revert GatewayFrozen();
        emit SetIdGateway(idGateway, _idGateway);
        idGateway = _idGateway;
    }

    /**
     * @inheritdoc IIdRegistry
     */
    function freezeIdGateway() external onlyOwner {
        if (gatewayFrozen) revert GatewayFrozen();
        emit FreezeIdGateway(idGateway);
        gatewayFrozen = true;
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    function bulkRegisterIds(
        BulkRegisterData[] calldata ids
    ) external onlyMigrator {
        // Safety: i can be incremented unchecked since it is bound by ids.length.
        unchecked {
            for (uint256 i = 0; i < ids.length; i++) {
                BulkRegisterData calldata id = ids[i];
                if (idOf[id.custody] != 0) revert HasId();
                _unsafeRegister(id.fid, id.custody, id.recovery);
            }
        }
    }

    function bulkRegisterIdsWithDefaultRecovery(
        BulkRegisterDefaultRecoveryData[] calldata ids,
        address recovery
    ) external onlyMigrator {
        // Safety: i can be incremented unchecked since it is bound by ids.length.
        unchecked {
            for (uint256 i = 0; i < ids.length; i++) {
                BulkRegisterDefaultRecoveryData calldata id = ids[i];
                if (idOf[id.custody] != 0) revert HasId();
                _unsafeRegister(id.fid, id.custody, recovery);
            }
        }
    }

    function bulkResetIds(
        uint24[] calldata ids
    ) external onlyMigrator {
        // Safety: i can be incremented unchecked since it is bound by ids.length.
        unchecked {
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 id = ids[i];
                address custody = custodyOf[id];

                idOf[custody] = 0;
                custodyOf[id] = address(0);
                recoveryOf[id] = address(0);

                emit AdminReset(id);
            }
        }
    }

    function setIdCounter(
        uint256 _counter
    ) external onlyMigrator {
        emit SetIdCounter(idCounter, _counter);
        idCounter = _counter;
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    function verifyFidSignature(
        address custodyAddress,
        uint256 fid,
        bytes32 digest,
        bytes calldata sig
    ) external view returns (bool isValid) {
        isValid = idOf[custodyAddress] == fid && SignatureChecker.isValidSignatureNow(custodyAddress, digest, sig);
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifyTransferSig(uint256 fid, address to, uint256 deadline, address signer, bytes memory sig) internal {
        _verifySig(
            _hashTypedDataV4(keccak256(abi.encode(TRANSFER_TYPEHASH, fid, to, _useNonce(signer), deadline))),
            signer,
            deadline,
            sig
        );
    }

    function _verifyTransferAndChangeRecoverySig(
        uint256 fid,
        address to,
        address recovery,
        uint256 deadline,
        address signer,
        bytes memory sig
    ) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(TRANSFER_AND_CHANGE_RECOVERY_TYPEHASH, fid, to, recovery, _useNonce(signer), deadline)
                )
            ),
            signer,
            deadline,
            sig
        );
    }

    function _verifyChangeRecoveryAddressSig(
        uint256 fid,
        address from,
        address to,
        uint256 deadline,
        address signer,
        bytes memory sig
    ) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(abi.encode(CHANGE_RECOVERY_ADDRESS_TYPEHASH, fid, from, to, _useNonce(signer), deadline))
            ),
            signer,
            deadline,
            sig
        );
    }
}
