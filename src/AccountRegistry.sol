// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

error AccountHasId();
error AccountHasRecovery();
error AddressNotOwner();
error InvalidId();
error CustodyRecoveryDuplicate();

contract AccountRegistry {
    uint256 idCounter;
    mapping(address => uint256) public custodyAddressToid;
    event Register(uint256 indexed id, address indexed custodyAddress);

    function register() public {
        if (custodyAddressToid[msg.sender] != 0) revert AccountHasId();

        // Incrementing before assigning ensures that no one can claim the 0 ID. Performing this
        // unchecked also saves us about 100 GAS and is safe to do given the very large size of
        // uint256. Should audit this carefully and ensure that the overflow scenario can be
        // managed.
        unchecked {
            idCounter++;
        }

        // Optimization: Do you need to store the uint256 here? can you
        // save gas by using a truthy value and relying on the event
        // for the actual ID?
        custodyAddressToid[msg.sender] = idCounter;
        emit Register(idCounter, msg.sender);
    }

    /*
     * Recovery
     */

    mapping(uint256 => address) public idToRecoveryAddress;
    mapping(uint256 => uint256) public idToTransferClock;
    mapping(uint256 => uint256) public idToTransferDestination;

    event SetRecovery(address indexed recovery, uint256 indexed id);

    event TransferRequested(
        address indexed to,
        uint256 indexed id,
        address indexed by,
        uint256 nonce
    );

    event TransferCompleted(
        address indexed to,
        uint256 indexed id,
        address indexed performedBy,
        address approvedBy
    );

    function setRecovery(uint256 id, address newRecoveryAddress) public {
        if (id == 0) revert InvalidId();
        if (custodyAddressToid[msg.sender] != id) revert AddressNotOwner();
        if (idToRecoveryAddress[id] != address(0)) revert AccountHasRecovery();
        if (newRecoveryAddress == msg.sender) revert CustodyRecoveryDuplicate();
        idToRecoveryAddress[id] = newRecoveryAddress;
        emit SetRecovery(newRecoveryAddress, id);
    }

    function requestTransfer(uint256 id, address to) public {
        // check msg.sender == idToRecoveryAddress[id] || idToCustodyAddress[id]
        // assert to != msg.sender
        // assert to != idToRecoveryAddress[id]
        // if (!idToRecoveryAddress[id]) { _transfer(id, to) }
        // else....
        // set idToTransferDestination[id] == to
        // emit TransferRequested
    }

    // A transfer can be cancelled by either party 1hr after it is created.
    function cancelTransfer(uint256 id, address to) public {
        // check msg.sender == idToRecoveryAddress[id] || idToCustodyAddress[id]
        // assert idToTransferClock[id] != 0
        // assert blockHeight - idToTransferClock[id] > (258 blocks, ~1hr)
        // set idToTransferClock[id] = 0;
        // emit TransferCancelled();
    }

    function completeTransfer(uint256 id) public {
        // assert msg.sender == uuidToRecoveryAddress[id] || uuidToCustodyAddress[id]
        // assert idToTransferClock[id] > 0;
        // assert blockHeight - idToTransferClock[id] > (19_000 blocks, ~ 3d, 2h)
        // _transfer(id, uuidToTransferDestination[id]);
    }

    function _transfer(uint256 id, address to) public {
        // set uuidToCustodyAddress[id] = to
        // set idToTransferClock[id] = 0;
        // reset the recovery address
        // emit TransferCompleted()
    }
}
