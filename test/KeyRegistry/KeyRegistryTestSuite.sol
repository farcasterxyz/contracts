// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import {IdRegistryTestSuite} from "../IdRegistry/IdRegistryTestSuite.sol";
import {KeyRegistryHarness} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract KeyRegistryTestSuite is IdRegistryTestSuite {
    KeyRegistryHarness internal keyRegistry;

    function setUp() public virtual override {
        super.setUp();

        keyRegistry = new KeyRegistryHarness(address(idRegistry), 1 days, owner);
    }
}
