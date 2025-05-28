// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {TierRegistry} from "../../src/TierRegistry.sol";

contract TierRegistryHarness is TierRegistry {
    constructor(
        address _owner
    ) TierRegistry(_owner) {}

    function ownerRoleId() external pure returns (bytes32) {
        return OWNER_ROLE;
    }
}
