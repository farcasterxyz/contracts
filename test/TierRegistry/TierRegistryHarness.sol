// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {TierRegistry} from "../../src/TierRegistry.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC1271} from "openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract TierRegistryHarness is TierRegistry {
    constructor(
        address _owner
    ) TierRegistry(_owner) {}

    function ownerRoleId() external pure returns (bytes32) {
        return OWNER_ROLE;
    }
}
