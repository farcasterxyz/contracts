// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";

abstract contract Guardians is Ownable2Step, Pausable {
    mapping(address => bool) public guardians;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Add(address indexed guardian);
    event Remove(address indexed guardian);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyGuardian();

    modifier onlyGuardian() {
        if (msg.sender != owner() && !guardians[msg.sender]) {
            revert OnlyGuardian();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _initialOwner) {
        _transferOwnership(_initialOwner);
    }

    function addGuardian(address guardian) external onlyOwner {
        guardians[guardian] = true;
        emit Add(guardian);
    }

    function removeGuardian(address guardian) external onlyOwner {
        guardians[guardian] = false;
        emit Remove(guardian);
    }

    function pause() external onlyGuardian {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
