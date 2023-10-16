// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {RegistrationTestSuite} from "../Registration/RegistrationTestSuite.sol";

import {IdRegistry} from "../../src/IdRegistry.sol";
import {Bundler} from "../../src/Bundler.sol";

/* solhint-disable state-visibility */

abstract contract BundlerTestSuite is RegistrationTestSuite {
    Bundler bundler;

    function setUp() public virtual override {
        super.setUp();

        // Set up the BundleRegistry
        bundler = new Bundler(
            address(registration),
            address(storageRegistry),
            address(keyRegistry),
            address(this),
            owner
        );
    }

    // Assert that a given fname was correctly registered with id 1 and recovery
    function _assertSuccessfulRegistration(address account, address recovery) internal {
        assertEq(idRegistry.idOf(account), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    // Assert that a given fname was not registered and the contracts have no registrations
    function _assertUnsuccessfulRegistration(address account) internal {
        assertEq(idRegistry.idOf(account), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }
}
