// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Nonces} from "openzeppelin-latest/contracts/utils/Nonces.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";

import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Signatures} from "./lib/Signatures.sol";
import {TrustedCaller} from "./lib/TrustedCaller.sol";

/**
 * @title IdRegistry
 *
 * @notice See ../docs/docs.md for an overview.
 */
contract IdRegistry is IIdRegistry, TrustedCaller, Signatures, Pausable, EIP712, Nonces {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when the caller does not have the authority to perform the action.
    error Unauthorized();

    /// @dev Revert when the caller must have an fid but does not have one.
    error HasNoId();

    /// @dev Revert when the destination must be empty but has an fid.
    error HasId();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when a new Farcaster ID is registered.
     *
     *      Hubs listen for this and update their address-to-fid mapping by adding `to` as the
     *      current owner of `id`. Hubs assume the invariants:
     *
     *      1. Two Register events can never emit with the same `id`
     *
     *      2. Two Register(alice, ..., ...) cannot emit unless a Transfer(alice, bob, ...) emits
     *          in between, where bob != alice.
     *
     * @param to       The custody address that owns the fid
     * @param id       The fid that was registered.
     * @param recovery The address that can initiate a recovery request for the fid.
     */
    event Register(address indexed to, uint256 indexed id, address recovery);

    /**
     * @dev Emit an event when an fid is transferred to a new custody address.
     *
     *      Hubs listen to this event and atomically change the current owner of `id`
     *      from `from` to `to` in their address-to-fid mapping. Hubs assume the invariants:
     *
     *      1. A Transfer(..., alice, ...) cannot emit if the most recent event for alice is
     *         Register (alice, ..., ...)
     *
     *      2. A Transfer(alice, ..., id) cannot emit unless the most recent event with that id is
     *         Transfer(..., alice, id) or Register(alice, id, ...)
     *
     * @param from The custody address that previously owned the fid.
     * @param to   The custody address that now owns the fid.
     * @param id   The fid that was transferred.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /**
     * @dev Emit an event when an fid is recovered.
     *
     * @param from The custody address that previously owned the fid.
     * @param to   The custody address that now owns the fid.
     * @param id   The fid that was recovered.
     */
    event Recover(address indexed from, address indexed to, uint256 indexed id);

    /**
     * @dev Emit an event when a Farcaster ID's recovery address changes. It is possible for this
     *      event to emit multiple times in a row with the same recovery address.
     *
     * @param id       The fid whose recovery address was changed.
     * @param recovery The new recovery address.
     */
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Defined for compatibility with tools like Etherscan that detect fid
     *      transfers as token transfers. This is intentionally lowercased.
     */
    string public constant name = "Farcaster FID";

    /**
     * @dev Contract version specified using Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.08.23";

    bytes32 public constant REGISTER_TYPEHASH =
        keccak256("Register(address to,address recovery,uint256 nonce,uint256 deadline)");

    bytes32 public constant TRANSFER_TYPEHASH =
        keccak256("Transfer(uint256 fid,address to,uint256 nonce,uint256 deadline)");

    bytes32 public constant CHANGE_RECOVERY_ADDRESS_TYPEHASH =
        keccak256("ChangeRecoveryAddress(uint256 fid,address recovery,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The last Farcaster id that was issued.
     */
    uint256 public idCounter;

    /**
     * @dev Maps each address to an fid, or zero if it does not own an fid.
     */
    mapping(address owner => uint256 fid) public idOf;

    /**
     * @dev Maps each fid to an address that can initiate a recovery.
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
    constructor(address _initialOwner) TrustedCaller(_initialOwner) EIP712("Farcaster IdRegistry", "1") {}

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new Farcaster ID (fid) to the caller. The caller must not have an fid.
     *         The contract must not be in the Registrable (trustedOnly = 0) state.
     *
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     *
     * @return fid registered FID.
     */
    function register(address recovery) external returns (uint256 fid) {
        return _register(msg.sender, recovery);
    }

    /**
     * @notice Register a new Farcaster ID (fid) to any address. A signed message from the address
     *         must be provided which approves both the to and the recovery. The address must not
     *         have an fid. The contract must be in the Registrable (trustedOnly = 0) state.
     *
     * @param to       Address which will own the fid.
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Register signature signed by the to address.
     *
     * @return fid registered FID.
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external returns (uint256 fid) {
        /* Revert if signature is invalid */
        _verifyRegisterSig({to: to, recovery: recovery, deadline: deadline, sig: sig});
        return _register(to, recovery);
    }

    /**
     * @notice Register a new Farcaster ID (fid) to any address. The address must not have an fid.
     *         The contract must be in the Seedable (trustedOnly = 1) state.
     *
     * @param to       The address which will own the fid.
     * @param recovery The address which can recover the fid.
     *
     * @return fid registered FID.
     */
    function trustedRegister(address to, address recovery) external onlyTrustedCaller returns (uint256 fid) {
        fid = _unsafeRegister(to, recovery);
        emit Register(to, idCounter, recovery);
    }

    /**
     * @dev Registers an fid and sets up a recovery address for a target. The contract must not be
     *      in the Seedable (trustedOnly = 1) state and target must not have an fid.
     */
    function _register(address to, address recovery) internal whenNotTrusted returns (uint256 fid) {
        fid = _unsafeRegister(to, recovery);
        emit Register(to, idCounter, recovery);
    }

    /**
     * @dev Registers an fid and sets up a recovery address for a target. Does not check all
     *      invariants or emit events.
     */
    function _unsafeRegister(address to, address recovery) internal whenNotPaused returns (uint256 fid) {
        /* Revert if the target(to) has an fid */
        if (idOf[to] != 0) revert HasId();

        /* Safety: idCounter won't realistically overflow. */
        unchecked {
            /* Incrementing before assignment ensures that no one gets the 0 fid. */
            fid = ++idCounter;
        }

        idOf[to] = fid;
        recoveryOf[fid] = recovery;
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer the fid owned by this address to another address that does not have an fid.
     *         A signed Transfer message from the destination address must be provided.
     *
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
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
     * @notice Transfer the fid owned by the from address to another address that does not
     *         have an fid. Caller must provide two signed Transfer messages: one signed by
     *         the from address and one signed by the to address.
     *
     * @param from         The owner address of the fid to transfer.
     * @param to           The address to transfer the fid to.
     * @param fromDeadline Expiration timestamp of the from signature.
     * @param fromSig      EIP-712 Transfer signature signed by the from address.
     * @param toDeadline   Expiration timestamp of the to signature.
     * @param toSig        EIP-712 Transfer signature signed by the to address.
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
        delete idOf[from];

        emit Transfer(from, to, id);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the recovery address of the fid owned by the caller.
     *
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
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
     * @notice Change the recovery address of fid owned by the owner. Caller must provide an
     *         EIP-712 ChangeRecoveryAddress message signed by the owner.
     *
     * @param owner    Custody address of the fid whose recovery address will be changed.
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
     * @param deadline Expiration timestamp of the ChangeRecoveryAddress signature.
     * @param sig      EIP-712 ChangeRecoveryAddress message signed by the owner address.
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

        _verifyChangeRecoveryAddressSig({fid: ownerId, recovery: recovery, deadline: deadline, signer: owner, sig: sig});

        /* Change the recovery address */
        recoveryOf[ownerId] = recovery;

        emit ChangeRecoveryAddress(ownerId, recovery);
    }

    /**
     * @notice Transfer the fid from the from address to the to address. Must be called by the
     *         recovery address. A signed message from the to address must be provided.
     *
     * @param from     The address that currently owns the fid.
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
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
     * @notice Transfer the fid owned by the from address to another address that does not
     *         have an fid. Caller must provide two signed Transfer messages: one signed by
     *         the recovery address and one signed by the to address.
     *
     * @param from             The owner address of the fid to transfer.
     * @param to               The address to transfer the fid to.
     * @param recoveryDeadline Expiration timestamp of the recovery signature.
     * @param recoverySig      EIP-712 Transfer signature signed by the recovery address.
     * @param toDeadline       Expiration timestamp of the to signature.
     * @param toSig            EIP-712 Transfer signature signed by the to address.
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
     * @notice Pause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verify that a signature was produced by the custody address that owns an fid.
     *
     * @param custodyAddress   The address to check the signature of.
     * @param fid              The fid to check the signature of.
     * @param digest           The digest that was signed.
     * @param sig              The signature to check.
     *
     * @return isValid Whether provided signature is valid.
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

    function _verifyRegisterSig(address to, address recovery, uint256 deadline, bytes memory sig) internal {
        _verifySig(
            _hashTypedDataV4(keccak256(abi.encode(REGISTER_TYPEHASH, to, recovery, _useNonce(to), deadline))),
            to,
            deadline,
            sig
        );
    }

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
        address recovery,
        uint256 deadline,
        address signer,
        bytes memory sig
    ) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(abi.encode(CHANGE_RECOVERY_ADDRESS_TYPEHASH, fid, recovery, _useNonce(signer), deadline))
            ),
            signer,
            deadline,
            sig
        );
    }
}
