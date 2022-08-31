// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ERC2771Context} from "../lib/openzeppelin-contracts/contracts/metatx/ERC2771Context.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {Context} from "openzeppelin/contracts/utils/Context.sol";

/**
 * @title IDRegistry
 * @author varunsrin
 * @custom:version 0.1
 *
 * @notice IDRegistry issues new farcaster account id's (fids) and maintains a mapping between the fid
 *         and the custody address that owns it. It implements a recovery system which allows a fid
 *         to be recovered if the custody address is lost.
 *
 * @dev Function calls use payable to marginally reduce gas usage.
 */
contract IDRegistry is ERC2771Context, Ownable {
    // solhint-disable-next-line no-empty-blocks
    constructor(address _forwarder) ERC2771Context(_forwarder) Ownable() {}

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized(); // The caller does not have the authority to perform this action.
    error ZeroId(); // The id is zero, which is invalid
    error HasId(); // The custody address has another id
    error Registrable(); // The trusted sender methods cannot be used when state is registrable

    error InvalidRecoveryAddr(); // The recovery cannot be the same as the custody address
    error NoRecovery(); // The recovery request for this id could not be found
    error Escrow(); // The recovery request is still in escrow

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery, string url);

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event ChangeHome(uint256 indexed id, string url);

    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);

    event RequestRecovery(address indexed from, address indexed to, uint256 indexed id);

    event CancelRecovery(uint256 indexed id);

    event ChangeTrustedSender(address indexed trustedSender);

    event DisableTrustedRegister();

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks the last farcaster id that was issued
    uint256 internal idCounter;

    /// @notice The address controlled by the Farcaster Invite service that is allowed to call trustedRegister
    address internal _trustedSender;

    /// @notice Flag that determines if registration can occur through trustedRegister or register
    /// @dev This value can only be changed to zero
    uint256 internal _trustedRegisterEnabled = 1;

    /// @notice Returns the farcaster id for an address
    mapping(address => uint256) internal _idOf;

    /// @notice Returns the recovery address for a farcaster id
    mapping(uint256 => address) internal _recoveryOf;

    /// @notice Returns the block timestamp if there is an active recovery for a farcaster id, or 0 if none
    mapping(uint256 => uint256) internal _recoveryClockOf;

    /// @notice Returns the destination address for the most recent recovery attempt for a farcaster id
    /// @dev This value is left dirty to save gas and should not be used to determine the state of a recovery
    mapping(uint256 => address) internal _recoveryDestinationOf;

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a Farcaster ID
     *
     * @param to the address which will own the fid
     * @param recovery the address which can recover the id
     * @param url the home url for the fid
     */
    function register(
        address to,
        address recovery,
        string calldata url
    ) external payable {
        if (_trustedRegisterEnabled == 1) revert Unauthorized();

        // Assumption: we don't worry if to==address(0) since that only happen once after which the _register reverts
        _register(to, recovery);

        // Assumption: the most recent value of the idCounter must equal the id of this user
        emit Register(to, idCounter, recovery, url);
    }

    /**
     * @notice Register a Farcaster ID
     *
     * @param to the address which will own the fid
     * @param recovery the address which can recover the id
     * @param url the home url for the fid
     */
    function trustedRegister(
        address to,
        address recovery,
        string calldata url
    ) external payable {
        if (_trustedRegisterEnabled == 0) revert Registrable();
        if (_msgSender() != _trustedSender) revert Unauthorized();

        // Assumption: we don't worry if to==address(0) since that only happen once after which the _register reverts
        _register(to, recovery);

        // Assumption: the most recent value of the idCounter must equal the id of this user
        emit Register(to, idCounter, recovery, url);
    }

    /**
     * @notice Update the Home URL by emitting it as an event
     *
     * @param url the url to emit
     */
    function changeHome(string calldata url) external payable {
        uint256 id = _idOf[_msgSender()];
        if (id == 0) revert ZeroId();

        emit ChangeHome(id, url);
    }

    // Perf: inlining this logic into functions can save ~ 20-40 gas per call
    function _register(address to, address recovery) internal {
        if (_idOf[to] != 0) revert HasId();

        unchecked {
            // Safety: this is a uint256 value and each transaction increments it by one. overflowing would require
            // spending ~ 2^81 gas to reach the max value (theoretically possible but not practically possible).
            idCounter++;
        }

        // Incrementing before assigning ensures that 0 is never issued as a valid ID.
        _idOf[to] = idCounter;
        _recoveryOf[idCounter] = recovery;
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfers an id from the current custodial address to the provided address, as long
     *         as the caller is the custodian.
     *
     * @param to The address to transfer the id to.
     */
    function transfer(address to) external payable {
        address sender = _msgSender();
        uint256 id = _idOf[sender];

        if (id == 0) revert ZeroId();
        if (_idOf[to] != 0) revert HasId();

        _unsafeTransfer(id, sender, to);
    }

    /**
     * @dev Moves ownership of an id to a new address. This function is unsafe because it does
     *      not perform any invariant checks.
     */
    function _unsafeTransfer(
        uint256 id,
        address from,
        address to
    ) internal {
        _idOf[to] = id;
        _idOf[from] = 0;

        // Perf: Checking before assigning is more gas efficient since this is often false
        if (_recoveryClockOf[id] != 0) delete _recoveryClockOf[id];
        _recoveryOf[id] = address(0);

        emit Transfer(from, to, id);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * INVARIANT 1: if _msgSender() == _recoveryOf[_idOf[addr]] then _idOf[addr] != 0
     * during invocation of requestRecovery, completeRecovery and cancelRecovery
     *
     *
     * 1. at the start, _idOf[addr] = 0 and _recoveryOf[_idOf[addr]] == address(0) ∀ addr
     *
     * 2. assume that _msgSender() != address(0) for all instances of _msgSender()
     *
     * 3. recoveryOf[addr] can be made a non-zero address only by register, trustedRegister
     *    changeRecoveryAddress, which requires _idOf[addr] != 0
     *
     * 4. _idOf[addr] can only be made 0 again  by transfer and completeRecovery, which ensures
     *    recoveryOf[addr] == address(0)
     **/

    /**
     * INVARIANT 2: if _recoveryClockOf[_idOf[address]] != 0 then _idOf[addr] != 0
     *
     *
     * 1. at the start, _idOf[addr] = 0 and _recoveryClockOf[_idOf[addr]] == 0 ∀ addr
     *
     * 2. _recoveryClockOf[_idOf[addr]] can only be made non-zero by requestRecovery, which
     *    requires _idOf[addr] != 0
     *
     * 3. _idOf[addr] can only be made zero again by transfer or completeRecovery, which ensures
     *    _recoveryClockOf[id[addr]] == 0
     */

    /**
     * @notice Choose a recovery address which has the ability to transfer the caller's id to a new
     *         address. The transfer happens in two steps - a request, and a complete which must
     *         occur after the escrow period has passed. During escrow, the custody address can
     *         cancel the transaction. The recovery address can be changed by the custody address
     *         at any time, or removed by setting it to 0x0. Changing a recovery address will not
     *         unset a currently active recovery request, that must be explicitly cancelled.
     *
     * @param recovery the address to set as the recovery.
     */
    function changeRecoveryAddress(address recovery) external payable {
        uint256 id = _idOf[_msgSender()];

        if (id == 0) revert ZeroId();

        _recoveryOf[id] = recovery;
        emit ChangeRecoveryAddress(id, recovery);

        if (_recoveryClockOf[id] != 0) delete _recoveryClockOf[id];
    }

    /**
     * @notice Request a transfer of an existing id to a new address by calling this function from the recovery
     *         address. The request can be completed after escrow period has passed.
     *
     * @dev The escrow period is tracked using a clock which is set to zero when no recovery request is active, and is
     *       set to the block timestamp when a request is opened.
     *
     * @param from the address that currently owns the id.
     * @param to the address to transfer the id to.
     */
    function requestRecovery(address from, address to) external payable {
        uint256 id = _idOf[from];

        if (_msgSender() != _recoveryOf[id]) revert Unauthorized();
        // Assumption: id != 0 because of invariant 1

        if (_idOf[to] != 0) revert HasId();

        _recoveryClockOf[id] = block.timestamp;
        _recoveryDestinationOf[id] = to;
        emit RequestRecovery(from, to, id);
    }

    /**
     * @notice Complete a transfer of an existing id to a new address by calling this function from
     *         the recovery address. The request can be completed if the escrow period has passed.
     *
     * @param from the address that currently owns the id.
     */
    function completeRecovery(address from) external payable {
        uint256 id = _idOf[from];
        address to = _recoveryDestinationOf[id];

        if (_msgSender() != _recoveryOf[id]) revert Unauthorized();
        if (_recoveryClockOf[id] == 0) revert NoRecovery();
        // Assumption: id != 0 because of invariant 1 and 2 (either asserts this)

        if (block.timestamp < _recoveryClockOf[id] + 3 days) revert Escrow();
        if (_idOf[to] != 0) revert HasId();

        _unsafeTransfer(id, from, to);
    }

    /**
     * @notice Cancel the recovery of an existing id by calling this function from the recovery
     *         or custody address. The request can be completed if the escrow period has passed.
     *
     * @param from the address that currently owns the id.
     */
    function cancelRecovery(address from) external payable {
        uint256 id = _idOf[from];
        address sender = _msgSender();

        if (sender != from && sender != _recoveryOf[id]) revert Unauthorized();
        // Assumption: id != 0 because of invariant 1

        if (_recoveryClockOf[id] == 0) revert NoRecovery();
        delete _recoveryClockOf[id];

        emit CancelRecovery(id);
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Changes the address from which registerTrusted calls can be made
     */
    function changeTrustedSender(address newTrustedSender) external payable onlyOwner {
        _trustedSender = newTrustedSender;
        emit ChangeTrustedSender(newTrustedSender);
    }

    /**
     * @notice Disables registerTrusted and enables register calls from any address.
     */
    function disableTrustedRegister() external payable onlyOwner {
        _trustedRegisterEnabled = 0;
        emit DisableTrustedRegister();
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
