// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Context} from "openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {ERC2771Context} from "openzeppelin-contracts/contracts/metatx/ERC2771Context.sol";

/**
 * @title IdRegistry
 * @author @v
 * @custom:version 2.0.0
 *
 * @notice IdRegistry lets any ETH address claim a unique Farcaster ID (fid). An address can own
 *         one fid at a time and may transfer it to another address. The IdRegistry starts in the
 *         seedable state where only a trusted caller can register fids and later moves to an open
 *         state where any address can register an fid. The Registry implements a recovery system
 *         which lets the address that owns an fid nominate a recovery address that can transfer
 *         the fid to a new address after a delay.
 */
contract IdRegistry is ERC2771Context, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Contains the state of the most recent recovery attempt.
     * @param destination Destination of the current recovery or address(0) if no active recovery.
     * @param timestamp Timestamp of the current recovery or zero if no active recovery.
     */
    struct RecoveryState {
        address destination;
        uint40 timestamp;
    }

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

    /// @dev Revert if a recovery operation is called when there is no active recovery.
    error NoRecovery();

    /// @dev Revert when completeRecovery() is called before the escrow period has elapsed.
    error Escrow();

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when a new Farcaster ID is registered.
     *
     * @param to       The custody address that owns the fid
     * @param id       The fid that was registered.
     * @param recovery The address that can initiate a recovery request for the fid
     */
    event Register(address indexed to, uint256 indexed id, address recovery);

    /**
     * @dev Emit an event when a Farcaster ID is transferred to a new custody address.
     *
     * @param from The custody address that previously owned the fid
     * @param to   The custody address that now owns the fid
     * @param id   The fid that was transferred.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /**
     * @dev Emit an event when a Farcaster ID's recovery address is updated
     *
     * @param id       The fid whose recovery address was updated.
     * @param recovery The new recovery address.
     */
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);

    /**
     * @dev Emit an event when a recovery request is initiated for a Farcaster Id
     *
     * @param from The custody address of the fid being recovered.
     * @param to   The destination address for the fid when the recovery is completed.
     * @param id   The id being recovered.
     */
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed id);

    /**
     * @dev Emit an event when a recovery request is cancelled
     *
     * @param by  The address that cancelled the recovery request
     * @param id  The id being recovered.
     */
    event CancelRecovery(address indexed by, uint256 indexed id);

    /**
     * @dev Emit an event when the trusted caller is modified.
     *
     * @param trustedCaller The address of the new trusted caller.
     */
    event ChangeTrustedCaller(address indexed trustedCaller);

    /**
     * @dev Emit an event when the trusted only state is disabled.
     */
    event DisableTrustedOnly();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant ESCROW_PERIOD = 3 days;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The last farcaster id that was issued.
     */
    uint256 internal idCounter;

    /**
     * @dev The Farcaster Invite service address that is allowed to call trustedRegister.
     */
    address internal trustedCaller;

    /**
     * @dev The address is allowed to call _completeTransferOwnership() and become the owner. Set to
     *      address(0) when no ownership transfer is pending.
     */
    address internal pendingOwner;

    /**
     * @dev Allows calling trustedRegister() when set 1, and register() when set to 0. The value is
     *      set to 1 and can be changed to 0, but never back to 1.
     */
    uint256 internal trustedOnly = 1;

    /**
     * @notice Maps each address to a fid, or zero if it does not own a fid.
     */
    mapping(address => uint256) public idOf;

    /**
     * @dev Maps each fid to an address that can initiate a recovery.
     */
    mapping(uint256 => address) internal recoveryOf;

    /**
     * @dev Maps each fid to a RecoveryState.
     */
    mapping(uint256 => RecoveryState) internal recoveryStateOf;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the owner of the contract to the deployer and configure the trusted forwarder.
     *
     * @param _forwarder The address of the ERC2771 forwarder contract that this contract trusts to
     *                   verify the authenticity of signed meta-transaction requests.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(address _forwarder) ERC2771Context(_forwarder) Ownable() {}

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new, unique Farcaster ID (fid) to an address that doesn't have one during
     *         the seedable phase.
     *
     * @param to       Address which will own the fid
     * @param recovery Address which can recover the fid
     */
    function register(address to, address recovery) external {
        /* Revert if the contract is in the seedable (trustedOnly) state  */
        if (trustedOnly == 1) revert Seedable();

        _unsafeRegister(to, recovery);

        emit Register(to, idCounter, recovery);
    }

    /**
     * @notice Register a new unique Farcaster ID (fid) for an address that does not have one. This
     *         can only be invoked by the trusted caller when trustedOnly is set to 1.
     *
     * @param to       The address which will control the fid
     * @param recovery The address which can recover the fid
     */
    function trustedRegister(address to, address recovery) external {
        /* Revert if the contract is not in the seedable(trustedOnly) state */
        if (trustedOnly == 0) revert Registrable();

        /* 
         * Revert if the caller is not the trusted caller 
         * Perf: Use msg.sender instead of msgSender() to save 100 gas since meta-tx are not needed
         */
        if (msg.sender != trustedCaller) revert Unauthorized();

        _unsafeRegister(to, recovery);

        emit Register(to, idCounter, recovery);
    }

    /**
     * @dev Registers a new, unique fid and sets up a recovery address for a caller without
     *      checking all invariants or emitting events.
     */
    function _unsafeRegister(address to, address recovery) internal {
        /* Revert if the destination(to) already has an fid */
        if (idOf[to] != 0) revert HasId();

        /* 
         * Safety: idCounter cannot realistically overflow, and incrementing before assignment
         * ensures that the id 0 is never assigned to an address.
         */
        unchecked {
            idCounter++;
        }

        /* Perf: Don't check to == address(0) to save 29 gas since 0x0 can only register 1 fid */
        idOf[to] = idCounter;
        recoveryOf[idCounter] = recovery;
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer the fid owned by this address to another address that does not have an fid.
     *         Supports ERC 2771 meta-transactions and can be called via a relayer.
     *
     * @param to The address to transfer the fid to.
     */
    function transfer(address to) external {
        address sender = _msgSender();
        uint256 id = idOf[sender];

        /* Revert if sender does not own an fid */
        if (id == 0) revert HasNoId();

        /* Revert if destination(to) already has an fid */
        if (idOf[to] != 0) revert HasId();

        _unsafeTransfer(id, sender, to);
    }

    /**
     * @dev Transfer the fid to another address and reset recovery without checking invariants.
     */
    function _unsafeTransfer(uint256 id, address from, address to) internal {
        /* Transfer ownership of the fid between addresses */
        idOf[to] = id;
        delete idOf[from];

        /* Clear the recovery address and reset active recovery requests */
        delete recoveryStateOf[id];
        delete recoveryOf[id];

        emit Transfer(from, to, id);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * INVARIANT 1: If msgSender() is a recovery address for an address, the latter must own an fid
     *
     * 1. idOf[addr] = 0 && recoveryOf[idOf[addr]] == address(0) ∀ addr
     *
     * 2. _msgSender() != address(0) ∀ _msgSender()
     *
     * 3. recoveryOf[addr] != address(0) ↔ idOf[addr] != 0
     *    see register(), trustedRegister() and changeRecoveryAddress()
     *
     * 4. idOf[addr] == 0 ↔ recoveryOf[addr] == address(0)
     *    see transfer() and completeRecovery()
     */

    /**
     * INVARIANT 2: If an address has a non-zero RecoveryState.timestamp, it must own an fid
     *
     * 1. idOf[addr] == 0  && recoveryStateOf[idOf[addr]].timestamp == 0 ∀ addr
     *
     * 2. recoveryStateOf[idOf[addr]].timestamp != 0 requires idOf[addr] != 0
     *    see requestRecovery()
     *
     * 3. idOf[addr] == 0 ↔ recoveryStateOf[id[addr]].timestamp == 0
     *    see transfer() and completeRecovery()
     */

    /**
     * INVARIANT 3: RecoveryState.timestamp and  RecoveryState.destination must both be zero or
     *              non-zero for a given fid. See register(), trustedRegister(),
     *              changeRecoveryAddress() and _unsafeTransfer() which enforce this.
     */

    /**
     * @notice Change the recovery address of the fid owned by the caller and reset active recovery
     *         requests. Supports ERC 2771 meta-transactions and can be called by a relayer.
     *
     * @param recovery The address which can recover the fid (set to 0x0 to disable recovery).
     */
    function changeRecoveryAddress(address recovery) external {
        /* Revert if the caller does not own an fid */
        uint256 id = idOf[_msgSender()];
        if (id == 0) revert HasNoId();

        /* Change the recovery address and reset active recovery requests */
        recoveryOf[id] = recovery;
        delete recoveryStateOf[id];

        emit ChangeRecoveryAddress(id, recovery);
    }

    /**
     * @notice Request a recovery of an fid to a new address if the caller is the recovery address.
     *         Supports ERC 2771 meta-transactions and can be called by a relayer.
     *
     * @param from The address that owns the fid
     * @param to   The address where the fid should be sent
     */
    function requestRecovery(address from, address to) external {
        /* Revert unless the caller is the recovery address */
        uint256 id = idOf[from];
        if (_msgSender() != recoveryOf[id]) revert Unauthorized();

        /* 
         * Set the recovery state 
         * Safety: id != 0 because of Invariant 1
         */
        recoveryStateOf[id].timestamp = uint40(block.timestamp);
        recoveryStateOf[id].destination = to;

        emit RequestRecovery(from, to, id);
    }

    /**
     * @notice Complete a recovery request and transfer the fid if the caller is the recovery
     *         address and the escrow period has passed. Supports ERC 2771 meta-transactions and
     *         can be called by a relayer.
     *
     * @param from The address that owns the fid.
     */
    function completeRecovery(address from) external {
        /* Revert unless the caller is the recovery address */
        uint256 id = idOf[from];
        if (_msgSender() != recoveryOf[id]) revert Unauthorized();

        /* Revert unless a recovery exists */
        RecoveryState memory state = recoveryStateOf[id];
        if (state.timestamp == 0) revert NoRecovery();

        /* 
         * Revert unless the escrow period has passed 
         * Safety: cannot overflow because state.timestamp was a block.timestamp
         */
        unchecked {
            if (block.timestamp < state.timestamp + ESCROW_PERIOD) {
                revert Escrow();
            }
        }

        /* Revert if the destination already has an fid */
        if (idOf[state.destination] != 0) revert HasId();

        /* 
         * Assumption 1: we don't need to check that the id still lives in the address because a
         * transfer would have reset timestamp to zero causing a revert
         * 
         * Assumption 2: id != 0 because of Invariant 1 and 2 (either asserts this)
         */
        _unsafeTransfer(id, from, state.destination);
    }

    /**
     * @notice Cancel an active recovery request if the caller is the recovery address or the
     *         custody address. Supports ERC 2771 meta-transactions and can be called by a relayer.
     *
     * @param from The address that owns the id.
     */
    function cancelRecovery(address from) external {
        uint256 id = idOf[from];
        address sender = _msgSender();

        /* Revert unless the caller is the recovery address or the custody address */
        if (sender != from && sender != recoveryOf[id]) revert Unauthorized();

        /* Revert unless an active recovery exists */
        if (recoveryStateOf[id].timestamp == 0) revert NoRecovery();

        /* Assumption: id != 0 because of Invariant 1 */
        delete recoveryStateOf[id];

        emit CancelRecovery(sender, id);
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the trusted caller by calling this from the contract's owner.
     *
     * @param _trustedCaller The address of the new trusted caller
     */
    function changeTrustedCaller(address _trustedCaller) external onlyOwner {
        /* Revert if the address is the zero address */
        if (_trustedCaller == address(0)) revert InvalidAddress();

        trustedCaller = _trustedCaller;

        emit ChangeTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Disable trustedRegister() and transition from seedable to registrable, which allows
     *        anyone to register an fid. This must be called by the contract's owner.
     */
    function disableTrustedOnly() external onlyOwner {
        delete trustedOnly;
        emit DisableTrustedOnly();
    }

    /**
     * @notice Overriden to prevent a single-step transfer of ownership
     */
    function transferOwnership(address /*newOwner*/ ) public view override onlyOwner {
        revert Unauthorized();
    }

    /**
     * @notice Start a request to transfer ownership to a new address ("pendingOwner"). This must
     *         be called by the owner, and can be cancelled by calling again with address(0).
     */
    function requestTransferOwnership(address newOwner) public onlyOwner {
        /* Revert if the newOwner is the zero address */
        if (newOwner == address(0)) revert InvalidAddress();

        pendingOwner = newOwner;
    }

    /**
     * @notice Complete a request to transfer ownership by calling from pendingOwner.
     */
    function completeTransferOwnership() external {
        /* Revert unless the caller is the pending owner */
        if (msg.sender != pendingOwner) revert Unauthorized();

        /* Safety: burning ownership is impossible since this can't be called from address(0) */
        _transferOwnership(msg.sender);

        /* Clean up state to prevent the function from being called again without a new request */
        delete pendingOwner;
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN ZEPPELIN OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}
