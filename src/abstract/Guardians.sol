// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";

import {IGuardians} from "../interfaces/abstract/IGuardians.sol";

abstract contract Guardians is IGuardians, Ownable2Step, Pausable {
    /**
     * @notice Mapping of addresses to guardian status.
     */
    mapping(address guardian => bool isGuardian) public guardians;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow only the owner or a guardian to call the
     *         protected function.
     */
    modifier onlyGuardian() {
        if (msg.sender != owner() && !guardians[msg.sender]) {
            revert OnlyGuardian();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the initial owner address.
     *
     * @param _initialOwner Address of the contract owner.
     */
    constructor(
        address _initialOwner
    ) {
        _transferOwnership(_initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IGuardians
     */
    function addGuardian(
        address guardian
    ) external onlyOwner {
        guardians[guardian] = true;
        emit Add(guardian);
    }

    /**
     * @inheritdoc IGuardians
     */
    function removeGuardian(
        address guardian
    ) external onlyOwner {
        guardians[guardian] = false;
        emit Remove(guardian);
    }

    /**
     * @inheritdoc IGuardians
     */
    function pause() external onlyGuardian {
        _pause();
    }

    /**
     * @inheritdoc IGuardians
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
