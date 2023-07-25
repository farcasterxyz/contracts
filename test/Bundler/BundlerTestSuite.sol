// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "../TestConstants.sol";

import {IdRegistryHarness} from "../Utils.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {StorageRentTestSuite} from "../StorageRent/StorageRentTestSuite.sol";
import {IdRegistryTestSuite} from "../IdRegistry/IdRegistryTestSuite.sol";

import {BundlerHarness} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract BundlerTestSuite is IdRegistryTestSuite, StorageRentTestSuite {
    // Instance of the BundleRegistry contract wrapped in its test wrapper
    BundlerHarness bundler;

    function setUp() public override(IdRegistryTestSuite, StorageRentTestSuite) {
        super.setUp();

        // Set up the BundleRegistry
        bundler = new BundlerHarness(
            address(idRegistry),
            address(storageRent),
            address(this),
            owner
        );
    }

    // Assert that a given fname was correctly registered with id 1 and recovery
    function _assertSuccessfulRegistration(address account, address recovery) internal {
        assertEq(idRegistry.idOf(account), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    // Assert that a given fname was not registered and the contracts have no registrations
    function _assertUnsuccessfulRegistration(address account) internal {
        assertEq(idRegistry.idOf(account), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }
}
