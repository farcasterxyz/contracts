// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

error AccountHasId();

contract AccountRegistry {
    uint256 idCounter;
    mapping(address => uint256) public custodyAddressToid;
    event Register(uint256 indexed id, address indexed custodyAddress);

    function register() public {
        if (custodyAddressToid[msg.sender] != 0) revert AccountHasId();

        // Incrementing before assigning ensures that no one can claim
        // the 0 ID
        idCounter++;

        // Optimization: Do you need to store the uint256 here? can you
        // save gas by using a truthy value and relying on the event
        // for the actual ID?
        custodyAddressToid[msg.sender] = idCounter;
        emit Register(idCounter, msg.sender);
    }
}
