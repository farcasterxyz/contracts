// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ERC2771Context} from "../lib/openzeppelin-contracts/contracts/metatx/ERC2771Context.sol";

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
contract IDRegistry is ERC2771Context {
    // solhint-disable-next-line no-empty-blocks
    constructor(address _trustedForwarder) ERC2771Context(_trustedForwarder) {}

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized(); // The caller does not have the authority to perform this action.
    error ZeroId(); // The id is zero, which is invalid
    error HasId(); // The custody address has another id

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

    // Last issued id
    uint256 private idCounter;

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
     * @notice Acquire a Farcaster ID for caller, if it doesn't already have one.
     *
     * @param recoveryAddress the initial recovery address, which can be set to zero to disable recovery
     *
     * @dev Ids begin at 1 and are issued sequentially by using a uint256 counter to track the last issued id. The
     *      zero (0) id is not allowed since zero represent the absence of a value in solidity.
     */
    function register(address recoveryAddress) external payable {
        _register(_msgSender(), recoveryAddress);
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

    /**
     * @notice Performs both register and changeHome in a single transaction.
     *
     * @param recoveryAddress the initial recovery address, which can be set to zero to disable recovery
     * @param url the home url to emit
     */
    function registerWithHome(address recoveryAddress, string calldata url) external payable {
        _register(_msgSender(), recoveryAddress);

        // Assumption: we can simply grab the latest value of the idCounter which should always equal the id of the
        // this user at this point in time.
        emit ChangeHome(idCounter, url);
    }

    function _register(address target, address recoveryAddress) internal {
        if (idOf[target] != 0) revert HasId();

        unchecked {
            // Safety: this is a uint256 value and each transaction increments it by one, which would require
            // spending ~ 2^81 gas to reach the max value (theoretically possible but not practically possible).
            idCounter++;
        }

        idOf[target] = idCounter;
        recoveryOf[idCounter] = recoveryAddress;
        emit Register(target, idCounter, recoveryAddress);
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
        address _msgSender = _msgSender();
        uint256 id = idOf[_msgSender];

        if (id == 0) revert ZeroId();

        if (idOf[to] != 0) revert HasId();

        _unsafeTransfer(id, _msgSender, to);
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
     * @param recoveryAddress the address to set as the recovery.
     */
    function changeRecoveryAddress(address recoveryAddress) external payable {
        uint256 id = idOf[_msgSender()];

        if (id == 0) revert ZeroId();

        recoveryOf[id] = recoveryAddress;
        emit ChangeRecoveryAddress(recoveryAddress, id);

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

        address _msgSender = _msgSender();

        if (_msgSender != from && _msgSender != recoveryOf[id]) revert Unauthorized();
        if (recoveryClockOf[id] == 0) revert NoRecovery();

        emit CancelRecovery(id);
        delete recoveryClockOf[id];
    }
}
