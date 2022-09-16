// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IdRegistryTestable} from "./Utils.sol";

import "forge-std/Test.sol";

/* solhint-disable state-visibility */

contract IdRegistryGasUsageTest is Test {
    IdRegistryTestable idRegistry;

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant TRUSTED_SENDER = address(0x123);
    address constant RECOVERY = address(0x6D1217BD164119E2ddE6ce1723879844FD73114e);
    string url = "https://farcaster.xyz";

    function setUp() public {
        idRegistry = new IdRegistryTestable(FORWARDER);
    }

    function testGasRegisterAndRecover() public {
        idRegistry.disableTrustedOnly();

        // Perform each action at least 5 times to get a good median value, since the first action
        // initializes storage and has extra costs

        for (uint256 i = 0; i < 15; i++) {
            // Register the name
            address alice = address(uint160(i));
            idRegistry.register(alice, RECOVERY, url);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);

            // Requesting a recovery should be done multiple times to get a good median value,
            // since it adds new storage slots.
            for (uint256 j = 0; j < 5; j++) {
                vm.prank(RECOVERY);
                idRegistry.requestRecovery(alice, RECOVERY);
            }

            // Cancelling and the recovery can be done once per user since it adds no new storage
            vm.prank(alice);
            idRegistry.cancelRecovery(alice);

            vm.prank(RECOVERY);
            idRegistry.requestRecovery(alice, address(uint160(i + 100)));

            vm.warp(block.timestamp + 7 days);
            vm.prank(RECOVERY);
            idRegistry.completeRecovery(alice);
        }
    }

    function testGasRegisterFromTrustedCaller() public {
        idRegistry.changeTrustedCaller(TRUSTED_SENDER);

        for (uint256 i = 0; i < 25; i++) {
            address alice = address(uint160(i));
            vm.prank(TRUSTED_SENDER);
            idRegistry.trustedRegister(alice, address(0), url);
            assertEq(idRegistry.idOf(alice), i + 1);
        }
    }
}
