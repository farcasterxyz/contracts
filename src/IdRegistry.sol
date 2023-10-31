// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Nonces} from "./lib/Nonces.sol";
import {Guardians} from "./lib/Guardians.sol";
import {Signatures} from "./lib/Signatures.sol";

/**
 * @title Farcaster IdRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract IdRegistry is IIdRegistry, Guardians, Signatures, EIP712, Nonces {
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
    string public constant VERSION = "2023.10.04";

    /**
     * @inheritdoc IIdRegistry
     */
    bytes32 public constant TRANSFER_TYPEHASH =
        keccak256("Transfer(uint256 fid,address to,uint256 nonce,uint256 deadline)");

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
     * @param _initialOwner Initial owner address.
     *
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(address _initialOwner) Guardians(_initialOwner) EIP712("Farcaster IdRegistry", "1") {}

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

        idOf[to] = fid;
        custodyOf[fid] = to;
        recoveryOf[fid] = recovery;
        emit Register(to, idCounter, recovery);
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdRegistry
     */
    function transfer(address to, uint256 deadline, bytes calldata sig) external {
        address from = msg.sender;
        uint256 fromId = idOf[from];

        /* Revert if the sender has no id */
        if (fromId == 0) revert HasNoId();
        /* Revert if recipient has an id */
        if (idOf[to] != 0) revert HasId();

        /* Revert if signature is invalid */
        _verifyTransferSig({fid: fromId, to: to, deadline: deadline, signer: to, sig: sig});

        _unsafeTransfer(fromId, from, to);
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
        uint256 fromId = idOf[from];

        /* Revert if the sender has no id */
        if (fromId == 0) revert HasNoId();
        /* Revert if recipient has an id */
        if (idOf[to] != 0) revert HasId();

        /* Revert if either signature is invalid */
        _verifyTransferSig({fid: fromId, to: to, deadline: fromDeadline, signer: from, sig: fromSig});
        _verifyTransferSig({fid: fromId, to: to, deadline: toDeadline, signer: to, sig: toSig});

        _unsafeTransfer(fromId, from, to);
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
    function changeRecoveryAddress(address recovery) external whenNotPaused {
        /* Revert if the caller does not own an fid */
        uint256 ownerId = idOf[msg.sender];
        if (ownerId == 0) revert HasNoId();

        /* Change the recovery address */
        recoveryOf[ownerId] = recovery;

        emit ChangeRecoveryAddress(ownerId, recovery);
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

        /* Change the recovery address */
        recoveryOf[ownerId] = recovery;

        emit ChangeRecoveryAddress(ownerId, recovery);
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
    function setIdGateway(address _idGateway) external onlyOwner {
        emit SetIdGateway(idGateway, _idGateway);
        idGateway = _idGateway;
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
