// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Context} from "openzeppelin/contracts/utils/Context.sol";
import {ECDSA} from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "openzeppelin-latest/contracts/utils/Nonces.sol";
import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
/**
 * @title IdRegistry
 * @author @v
 * @custom:version 2.0.0
 *
 * @notice IdRegistry lets any ETH address claim a unique Farcaster ID (fid). An address can own
 *         one fid at a time and may transfer it to another address.
 *
 *         The IdRegistry starts in the Seedable state where only a trusted caller can register
 *         fids and later moves to the Registrable where any address can register an fid. The
 *         Registry implements a recovery system which lets the address that owns an fid nominate
 *         a recovery address that can transfer the fid to a new address.
 */

contract IdRegistry is Ownable2Step, Pausable, EIP712, Nonces {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when the caller does not have the authority to perform the action.
    error Unauthorized();

    /// @dev Revert when the caller is required to have an fid but does not have one.
    error HasNoId();

    /// @dev Revert when the destination is required to be empty, but has an fid.
    error HasId();

    /// @dev Revert if trustedRegister is invoked after trustedCallerOnly is disabled.
    error Registrable();

    /// @dev Revert if register is invoked before trustedCallerOnly is disabled.
    error Seedable();

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

    /// @dev Revert when the signature provided is invalid.
    error InvalidSignature();

    /// @dev Revert when the block.timestamp is ahead of the signature deadline.
    error SignatureExpired();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when a new Farcaster ID is registered.
     *
     * @param to       The custody address that owns the fid
     * @param id       The fid that was registered.
     * @param recovery The address that can initiate a recovery request for the fid.
     */
    event Register(address indexed to, uint256 indexed id, address recovery);

    /**
     * @dev Emit an event when a Farcaster ID is transferred to a new custody address.
     *
     * @param from The custody address that previously owned the fid.
     * @param to   The custody address that now owns the fid.
     * @param id   The fid that was transferred.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /**
     * @dev Emit an event when a Farcaster ID's recovery address changes.
     *
     * @param id       The fid whose recovery address was changed.
     * @param recovery The new recovery address.
     */
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);

    /**
     * @dev Emit an event when the trusted caller is modified.
     *
     * @param trustedCaller The address of the new trusted caller.
     */
    event SetTrustedCaller(address indexed trustedCaller);

    /**
     * @dev Emit an event when the trusted only state is disabled.
     */
    event DisableTrustedOnly();

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant _REGISTER_TYPEHASH =
        keccak256("Register(address to,address recovery,uint256 nonce,uint256 deadline)");

    bytes32 internal constant _TRANSFER_TYPEHASH =
        keccak256("Transfer(address from,address to,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The admin address that is allowed to call trustedRegister.
     */
    address internal trustedCaller;

    /**
     * @dev Allows calling trustedRegister() when set 1, and register() when set to 0. The value is
     *      set to 1 and can be changed to 0, but never back to 1.
     */
    uint256 internal trustedOnly = 1;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The last farcaster id that was issued.
     */
    uint256 internal idCounter;

    /**
     * @dev Maps each address to a fid, or zero if it does not own a fid.
     */
    mapping(address => uint256) public idOf;

    /**
     * @dev Maps each fid to an address that can initiate a recovery.
     */
    mapping(uint256 => address) internal recoveryOf;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the owner of the contract to the deployer.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(address _owner) EIP712("Farcaster IdRegistry", "1") {}

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new Farcaster ID (fid) to the caller. The caller must not have an fid.
     *         Rthe contract must not be in the Registrable (trustedOnly = 0) state.
     *
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     */
    function register(address recovery) external returns (uint256 fid) {
        return _register(msg.sender, recovery);
    }

    /**
     * @notice Register a new Farcaster ID (fid) to any address. A signed message from the address
     *         must be provided. The address must not have an fid. The contract must be in the
     *         Registrable (trustedOnly = 0) state.
     *
     * @param to       Address which will own the fid.
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 signature signed by the to address.
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external returns (uint256 fid) {
        _verifyRegisterSig(to, recovery, deadline, sig);
        return _register(to, recovery);
    }

    /**
     * @notice Register a new Farcaster ID (fid) to any address. The address must not have an fid.
     *         The contract must be in the Seedable (trustedOnly = 1) state.
     *
     * @param to       The address which will own the fid.
     * @param recovery The address which can recover the fid.
     */
    function trustedRegister(address to, address recovery) external returns (uint256 fid) {
        if (trustedOnly == 0) revert Registrable();

        if (msg.sender != trustedCaller) revert Unauthorized();

        fid = _unsafeRegister(to, recovery);

        emit Register(to, idCounter, recovery);
    }

    /**
     * @dev Registers an fid and sets up a recovery address for a target. The contract must not be
     *      in the Seedable (trustedOnly = 1) state and the target must not have an fid.
     */
    function _register(address to, address recovery) internal returns (uint256 fid) {
        if (trustedOnly == 1) revert Seedable();

        fid = _unsafeRegister(to, recovery);

        emit Register(to, idCounter, recovery);
    }

    /**
     * @dev Registers an fid and sets up a recovery address for a target. Does not check all
     *      invariants or emit events. The contract must not be in the Seedable (trustedOnly = 1)
     *      state and the target must not have an fid.
     */
    function _unsafeRegister(address to, address recovery) internal whenNotPaused returns (uint256 fid) {
        /* Revert if the target(to) has an fid */
        if (idOf[to] != 0) revert HasId();

        /* Safety: idCounter won't realistically overflow. */
        unchecked {
            /* Incrementing before assignment ensures that no one gets the 0 fid. */
            fid = ++idCounter;
        }

        /* Perf: Save 29 gas by avoiding to == address(0) check since 0x0 can only register 1 fid */
        idOf[to] = fid;
        recoveryOf[fid] = recovery;
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer the fid owned by this address to another address that does not have an fid.
     *         Supports ERC 2771 meta-transactions and can be called via a relayer. A signed message
     *         from the destination address must be provided.
     *
     * @param to The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 signature signed by the to address.
     */
    function transfer(address to, uint256 deadline, bytes calldata sig) external {
        address from = msg.sender;
        uint256 fromId = idOf[from];

        /* Revert if the sender has no id or receipient has an id */
        if (fromId == 0) revert HasNoId();
        if (idOf[to] != 0) revert HasId();

        _verifyTransferSig(fromId, to, deadline, sig);

        _unsafeTransfer(fromId, from, to);
    }

    /**
     * @dev Transfer the fid to another address without checking invariants.
     */
    function _unsafeTransfer(uint256 id, address from, address to) internal {
        idOf[to] = id;
        delete idOf[from];

        emit Transfer(from, to, id);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * INVARIANT: If an address has a non-zero recovery address, it must own an fid.
     *
     * 1. idOf[addr] = 0 && recoveryOf[idOf[addr]] == address(0) ∀ addr
     *
     * 2. recoveryOf[addr] != address(0) ↔ idOf[addr] != 0
     *    see register(), trustedRegister() and changeRecoveryAddress()
     */

    /**
     * @notice Change the recovery address of the fid owned by the caller. Supports ERC 2771
     *         meta-transactions and can be called by a relayer.
     *
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
     */
    function changeRecoveryAddress(address recovery) external {
        /* Revert if the caller does not own an fid */
        uint256 ownerId = idOf[msg.sender];
        if (ownerId == 0) revert HasNoId();

        /* Change the recovery address */
        recoveryOf[ownerId] = recovery;

        emit ChangeRecoveryAddress(ownerId, recovery);
    }

    /**
     * @notice Transfer the fid from the from address to the to address. Must be called by the
     *         recovery address. Supports ERC 2771 meta-transactions and can be called via a
     *         relayer. A signed message from the to address must be provided.
     *
     * @param from     The address that currently owns the fid.
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 signature signed by the to address.
     */
    function recover(address from, address to, uint256 deadline, bytes calldata sig) external {
        /* Revert if from does not own an fid */
        uint256 fromId = idOf[from];
        if (fromId == 0) revert HasNoId();

        /* Revert if the caller is not the recovery address */
        address caller = msg.sender;
        address recoveryAddress = recoveryOf[fromId];
        if (recoveryAddress != caller) revert Unauthorized();

        /* Revert if destination(to) already has an fid */
        if (idOf[to] != 0) revert HasId();

        _verifyTransferSig(fromId, to, deadline, sig);

        _unsafeTransfer(fromId, from, to);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the trusted caller by calling this from the contract's owner.
     *
     * @param _trustedCaller The address of the new trusted caller
     */
    function setTrustedCaller(address _trustedCaller) external onlyOwner {
        if (_trustedCaller == address(0)) revert InvalidAddress();

        trustedCaller = _trustedCaller;
        emit SetTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Move from Seedable to Registrable where anyone can register an fid. Must be called
     *         by the contract's owner.
     */
    function disableTrustedOnly() external onlyOwner {
        delete trustedOnly;
        emit DisableTrustedOnly();
    }

    /**
     * @notice Pause all registrations. Must be called by the owner.
     */
    function pauseRegistration() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause all registrations. Must be called by the owner.
     */
    function unpauseRegistration() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifyRegisterSig(address to, address recovery, uint256 deadline, bytes memory sig) internal {
        if (block.timestamp >= deadline) revert SignatureExpired();
        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(_REGISTER_TYPEHASH, to, recovery, _useNonce(to), deadline)));

        address recovered = ECDSA.recover(digest, sig);
        if (recovered != to) revert InvalidSignature();
    }

    function _verifyTransferSig(uint256 fid, address to, uint256 deadline, bytes memory sig) internal {
        if (block.timestamp >= deadline) revert SignatureExpired();
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(_TRANSFER_TYPEHASH, fid, to, _useNonce(to), deadline)));

        address recovered = ECDSA.recover(digest, sig);
        if (recovered != to) revert InvalidSignature();
    }
}
