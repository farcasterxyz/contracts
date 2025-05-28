// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {TierRegistry} from "../../src/TierRegistry.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC1271} from "openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract TierRegistryHarness is TierRegistry {
    constructor(
        address _token,
        address _vault,
        address _roleAdmin,
        address _owner,
        address _operator,
        uint256 _minDays,
        uint256 _maxDays
    ) TierRegistry(_token, _vault, _roleAdmin, _owner, _operator, _minDays, _maxDays) {}

    function ownerRoleId() external pure returns (bytes32) {
        return OWNER_ROLE;
    }

    function operatorRoleId() external pure returns (bytes32) {
        return OPERATOR_ROLE;
    }
}
