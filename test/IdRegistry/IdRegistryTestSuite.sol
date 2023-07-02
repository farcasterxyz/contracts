// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IdRegistryHarness} from "../Utils.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";

/* solhint-disable state-visibility */

abstract contract IdRegistryTestSuite is TestSuiteSetup {
    IdRegistryHarness idRegistry;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);

    function setUp() public virtual override {
        super.setUp();

        idRegistry = new IdRegistryHarness(FORWARDER);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _register(address caller) internal {
        _registerWithRecovery(caller, address(0));
    }

    function _registerWithRecovery(address caller, address recovery) internal {
        idRegistry.disableTrustedOnly();
        vm.prank(caller);
        idRegistry.register(caller, recovery);
    }

    function _pauseRegistrations() public {
        vm.prank(owner);
        idRegistry.pauseRegistration();
        assertEq(idRegistry.paused(), true);
    }
}
