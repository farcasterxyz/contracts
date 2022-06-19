// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

// The caller does not have the authority to perform this action.
error Unauthorized();

// The id is invalid (i.e. equal to zero)
error IdInvalid();

// The custody address already owns an id and cannot receive another one.
error CustodyAddressInvalid();

// The address is the custody address for the id and cannot also become its recovery address
error RecoveryAddressInvalid();

// The recovery request for this id could not be found
error RecoveryNotFound();

// The recovery request is still in escrow
error RecoveryInEscrow();

/**
 * @title AccountRegistry
 * @author varunsrin
 * @custom:version 0.1
 * @notice AccountRegistry issues new farcaster account id's and maintains a mapping between the id
 *         and the custody address that owns it. It implements a recovery system which allows an id
 *         to be recovered if the address custodying it is lost.
 * @dev Function calls use payable to marginally reduce gas usage.
 */
contract AccountRegistry {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(uint256 indexed id, address indexed to);

    event Transfer(uint256 indexed id, address indexed to);

    event SetRecoveryAddress(address indexed recovery, uint256 indexed id);

    event RequestRecovery(uint256 indexed id, address indexed from, address indexed to);

    event CancelRecovery(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                         STORAGE
    //////////////////////////////////////////////////////////////*/

    // Last issued id
    uint256 idCounter;

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
     * @notice Acquire a new farcaster id for the calling address, assuming that it doesn't already
     *         have one. Id's are issued sequentially beginning at 1 and the caller becomes the
     *         custodian of the id.
     *
     * @dev Ids begin at 1 and are issued sequentially by using a uint256 counter to store the last
     *      issued id. The zero (0) id is not allowed since zero represent the absence of a value
     *      in solidity. The counter is incremented unchecked since this saves gas and is unlikely
     *      to overflow given that every increment requires a new on-chain transaction.
     */
    function register() external payable {
        if (idOf[msg.sender] != 0) revert CustodyAddressInvalid();

        unchecked {
            idCounter++;
        }

        idOf[msg.sender] = idCounter;
        emit Register(idCounter, msg.sender);
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
        uint256 id = idOf[msg.sender];

        if (id == 0) revert IdInvalid();

        if (idOf[to] != 0) revert CustodyAddressInvalid();

        _unsafeTransfer(id, msg.sender, to);
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

        emit Transfer(id, to);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    // Invariants
    //
    // 1. idOf[address] != 0 if msg.sender == recoveryOf[idOf[address]]
    //
    // recoveryOf[idOf[address]] != address(0) only if idOf[address] != 0 [setRecoveryAddress]
    // when idOf[address] == 0, recoveryof[idOf[address]] also == address(0) [_unsafeTransfer]
    // msg.sender != address(0) [by definition]
    //
    //
    // 2. idOf[address] != 0 if recoveryClockOf[idOf[address]] != 0
    //
    // recoveryClockOf[idOf[address]] != 0 only if idOf[address] != 0 [requestRecovery]
    // when idOf[address] == 0, recoveryClockOf[idOf[address]] also == 0 [_unsafeTransfer]

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
    function setRecoveryAddress(address recoveryAddress) external payable {
        uint256 id = idOf[msg.sender];

        if (id == 0) revert IdInvalid();
        if (recoveryAddress == msg.sender) revert RecoveryAddressInvalid();

        recoveryOf[id] = recoveryAddress;
        emit SetRecoveryAddress(recoveryAddress, id);
    }

    /**
     * @notice Request a transfer of an existing id to a new address by calling this function from
     *         the recovery address. The request can be completed after escrow period has passed.
     *
     * @param from the address that currently owns the id.
     *
     * @param to the address to transfer the id to.
     *
     * @dev The id != 0 assertion can be skipped because invariant 1 implies its correctness. The
     *       escrow period is tracked using a block clock which is set to zero when no recovery
     *       request is active, and is set to the block number when a request is opened.
     */
    function requestRecovery(address from, address to) external payable {
        uint256 id = idOf[from];

        if (msg.sender != recoveryOf[id]) revert Unauthorized();
        if (idOf[to] != 0) revert CustodyAddressInvalid();

        recoveryClockOf[id] = block.number;
        recoveryDestinationOf[id] = to;
        emit RequestRecovery(id, from, to);
    }

    /**
     * @notice Complete a transfer of an existing id to a new address by calling this function from
     *         the recovery address. The request can be completed if the escrow period has passed.
     *
     * @param from the address that currently owns the id.
     *
     * @dev The id != 0 assertion can be skipped because invariant 1 and 2 imply its correctness.
     */
    function completeRecovery(address from) external payable {
        uint256 id = idOf[from];
        address destination = recoveryDestinationOf[id];

        if (msg.sender != recoveryOf[id]) revert Unauthorized();
        if (recoveryClockOf[id] == 0) revert RecoveryNotFound();
        // Recovery escrow duration in blocks (20,000 blocks = ~2.7 - 3.2 days)
        if (block.number < recoveryClockOf[id] + 20_000) revert RecoveryInEscrow();
        if (idOf[destination] != 0) revert CustodyAddressInvalid();

        _unsafeTransfer(id, from, destination);
        recoveryClockOf[id] = 0;
    }

    /**
     * @notice Cancel the recovery of an existing id by calling this function from the recovery
     *         or custody address. The request can be completed if the escrow period has passed.
     *
     * @param from the address that currently owns the id.
     *
     * @dev The id != 0 assertion can be skipped because invariant 1 and 2 imply its correctness.
     */
    function cancelRecovery(address from) external payable {
        uint256 id = idOf[from];

        if (msg.sender != from && msg.sender != recoveryOf[id]) revert Unauthorized();
        if (recoveryClockOf[id] == 0) revert RecoveryNotFound();

        emit CancelRecovery(id);
        recoveryClockOf[id] = 0;
    }
}
