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
 *         to be recovered if the address custodying it is lost.
 *
 * @dev Function calls use payable to marginally reduce gas usage.
 */
contract IDRegistry is ERC2771Context, Ownable {
    // solhint-disable-next-line no-empty-blocks
    constructor(address _trustedForwarder) ERC2771Context(_trustedForwarder) Ownable() {}

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

    event Register(address indexed to, uint256 indexed id, address recovery);

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event ChangeHome(uint256 indexed id, string url);

    event ChangeRecoveryAddress(address indexed recovery, uint256 indexed id);

    event RequestRecovery(uint256 indexed id, address indexed from, address indexed to);

    event CancelRecovery(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    // The most recent fid issued by the contract.
    uint256 private idCounter;

    // The trusted sender for preregistration
    address public trustedSender;

    // Only allow calls to preregister from the trusted sender
    bool public trustedRegisterEnabled = true;

    // Mapping from custody address to id
    mapping(address => uint256) public idOf;

    // Mapping from id to recovery address
    mapping(uint256 => address) public recoveryOf;

    // Mapping from id to recovery start (in blocks)
    mapping(uint256 => uint256) public recoveryClockOf;

    // Mapping from id to recovery destination address
    mapping(uint256 => address) public recoveryDestinationOf;

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register an FID for the caller
     *
     * @param recovery the initial recovery address, which can be set to zero to disable recovery
     */
    // Optimization: if we don't need the recovery address and can avoid the assginment, we save about 2500 gas
    function register(address recovery) external payable {
        if (trustedRegisterEnabled) revert Unauthorized();
        _register(_msgSender(), recovery);
    }

    /**
     * @notice Register an FID for another address and configure all optional settings
     *
     * @dev Slightly more gas efficient than calling trustedRegister post-registration
     *
     * @param to the address to register an FID for
     * @param recovery the address which can perform recovery operations
     * @param url the home url for the FID
     */
    function register(
        address to,
        address recovery,
        string calldata url
    ) external payable {
        if (trustedRegisterEnabled) revert Unauthorized();
        _register(to, recovery);

        // Assumption: we can simply grab the latest value of the idCounter which should always equal the id of the
        // this user at this point in time.
        emit ChangeHome(idCounter, url);
    }

    /**
     * @notice Register an FID for another address and configure all optional settings
     *
     * @param to the address to register an FID for
     * @param recovery the address which can perform recovery operations, set to zero address to disable.
     * @param url the home url for the FID
     */
    function trustedRegister(
        address to,
        address recovery,
        string calldata url
    ) external payable {
        if (!trustedRegisterEnabled) revert Registrable();
        if (_msgSender() != trustedSender) revert Unauthorized();

        _register(to, recovery);

        // Assumption: we can simply grab the latest value of the idCounter which should always equal the id of the
        // this user at this point in time.
        emit ChangeHome(idCounter, url);
    }

    /**
     * @notice Update the Home URL by emitting it as an event
     *
     * @param url the url to emit
     */
    function changeHome(string calldata url) external payable {
        uint256 _id = idOf[_msgSender()];
        if (_id == 0) revert ZeroId();

        emit ChangeHome(_id, url);
    }

    // Optimization: inlining this logic into functions can save ~ 20-40 gas per call at the expense of contract size
    // and duplicating logic in solidity code.
    function _register(address to, address recovery) private {
        if (idOf[to] != 0) revert HasId();

        unchecked {
            // Safety: this is a uint256 value and each transaction increments it by one, which would require
            // spending ~ 2^81 gas to reach the max value (theoretically possible but not practically possible).
            idCounter++;
        }

        // Incrementing before assigning ensures that the first id issued is 1, and not 0.
        idOf[to] = idCounter;
        recoveryOf[idCounter] = recovery;
        emit Register(to, idCounter, recovery);
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
        uint256 id = idOf[sender];

        if (id == 0) revert ZeroId();

        if (idOf[to] != 0) revert HasId();

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
    ) private {
        idOf[to] = id;
        idOf[from] = 0;

        // since this is rarely true, checking before assigning is more gas efficient
        if (recoveryClockOf[id] != 0) recoveryClockOf[id] = 0;
        recoveryOf[id] = address(0);

        emit Transfer(from, to, id);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * INVARIANT 1:  idOf[address] != 0 if _msgSender() == recoveryOf[idOf[address]] during
     * invocation of requestRecovery, completeRecovery and cancelRecovery
     *
     * recoveryOf[idOf[address]] != address(0) only if idOf[address] != 0 [changeRecoveryAddress]
     * when idOf[address] == 0, recoveryof[idOf[address]] also == address(0) [_unsafeTransfer]
     * _msgSender() != address(0) [by definition]
     *
     * INVARIANT 2:  idOf[address] != 0 if recoveryClockOf[idOf[address]] != 0
     *
     * recoveryClockOf[idOf[address]] != 0 only if idOf[address] != 0 [requestRecovery]
     * when idOf[address] == 0, recoveryClockOf[idOf[address]] also == 0 [_unsafeTransfer]
     */

    /**
     * @notice Choose a recovery address which has the ability to transfer the caller's id to a new
     *         address. The transfer happens in two steps - a request, and a complete which must
     *         occur after the escrow period has passed. During escroew, the custody address can
     *         cancel the transaction. The recovery address can be changed by the custody address
     *         at any time, or removed by setting it to 0x0. Changing a recovery address will not
     *         unset a currently active recovery request, that must be explicitly cancelled.
     *
     * @param recovery the address to set as the recovery.
     */
    function changeRecoveryAddress(address recovery) external payable {
        uint256 id = idOf[_msgSender()];

        if (id == 0) revert ZeroId();

        recoveryOf[id] = recovery;
        emit ChangeRecoveryAddress(recovery, id);

        if (recoveryClockOf[id] != 0) {
            emit CancelRecovery(id);
            delete recoveryClockOf[id];
        }
    }

    /**
     * @notice Request a transfer of an existing id to a new address by calling this function from
     *         the recovery address. The request can be completed after escrow period has passed.
     *
     * @dev The id != 0 assertion can be skipped because of invariant 1. The escrow period is
     *       tracked using a clock which is set to zero when no recovery request is active, and is
     *       set to the block timestamp when a request is opened.
     *
     * @param from the address that currently owns the id.
     * @param to the address to transfer the id to.
     */
    function requestRecovery(address from, address to) external payable {
        uint256 id = idOf[from];

        if (_msgSender() != recoveryOf[id]) revert Unauthorized();
        if (idOf[to] != 0) revert HasId();

        recoveryClockOf[id] = block.timestamp;
        recoveryDestinationOf[id] = to;
        emit RequestRecovery(id, from, to);
    }

    /**
     * @notice Complete a transfer of an existing id to a new address by calling this function from
     *         the recovery address. The request can be completed if the escrow period has passed.
     *
     * @dev The id != 0 assertion can be skipped because of invariant 1 and 2.
     *
     * @param from the address that currently owns the id.
     */
    function completeRecovery(address from) external payable {
        uint256 id = idOf[from];
        address destination = recoveryDestinationOf[id];

        if (_msgSender() != recoveryOf[id]) revert Unauthorized();
        if (recoveryClockOf[id] == 0) revert NoRecovery();

        if (block.timestamp < recoveryClockOf[id] + 259_200) revert Escrow();
        if (idOf[destination] != 0) revert HasId();

        _unsafeTransfer(id, from, destination);
        recoveryClockOf[id] = 0;
    }

    /**
     * @notice Cancel the recovery of an existing id by calling this function from the recovery
     *         or custody address. The request can be completed if the escrow period has passed.
     *
     * @dev The id != 0 assertion can be skipped because of invariant 1 and 2.
     *
     * @param from the address that currently owns the id.
     */
    function cancelRecovery(address from) external payable {
        uint256 id = idOf[from];

        address sender = _msgSender();

        if (sender != from && sender != recoveryOf[id]) revert Unauthorized();
        if (recoveryClockOf[id] == 0) revert NoRecovery();

        emit CancelRecovery(id);
        delete recoveryClockOf[id];
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Changes the address from which registerTrusted calls can be made
     */
    function setTrustedSender(address _trustedSender) external onlyOwner {
        trustedSender = _trustedSender;
    }

    /**
     * @notice Disables registerTrusted and enables register calls from any address.
     */
    function disableTrustedRegister() external onlyOwner {
        trustedRegisterEnabled = false;
    }

    /*//////////////////////////////////////////////////////////////
                         OPEN ZEPPELIN OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function _msgSender() internal view override(Context, ERC2771Context) returns (address sender) {
        sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}
