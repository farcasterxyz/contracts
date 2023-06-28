// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";
import {IdRegistryHarness} from "../Utils.sol";

/* solhint-disable state-visibility */

contract IdRegistryGasUsageTest is IdRegistryTestSuite {
    address constant TRUSTED_SENDER = address(0x123);
    address constant RECOVERY = address(0x6D1217BD164119E2ddE6ce1723879844FD73114e);

    function testGasRegisterAndRecover() public {
        idRegistry.disableTrustedOnly();

        // Perform each action at least 5 times to get a good median value, since the first action
        // initializes storage and has extra costs

        for (uint256 i = 0; i < 15; i++) {
            address alice = address(uint160(i));
            idRegistry.register(alice, RECOVERY);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);

            vm.prank(RECOVERY);
            idRegistry.recover(alice, address(uint160(i + 100)));
        }
    }

    function testGasRegisterFromTrustedCaller() public {
        idRegistry.changeTrustedCaller(TRUSTED_SENDER);

        for (uint256 i = 0; i < 25; i++) {
            address alice = address(uint160(i));
            vm.prank(TRUSTED_SENDER);
            idRegistry.trustedRegister(alice, address(0));
            assertEq(idRegistry.idOf(alice), i + 1);
        }
    }
}
