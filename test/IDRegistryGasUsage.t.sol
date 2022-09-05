// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IDRegistryTestable} from "./Utils.sol";

import "forge-std/Test.sol";

/* solhint-disable state-visibility */

contract IDRegistryGasUsageTest is Test {
    IDRegistryTestable idRegistry;

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant TRUSTED_SENDER = address(0x123);
    string url = "https://farcaster.xyz";

    function setUp() public {
        idRegistry = new IDRegistryTestable(FORWARDER);
    }

    function testGasRegister() public {
        idRegistry.disableTrustedOnly();
        for (uint256 i = 0; i < 25; i++) {
            address alice = address(uint160(i));
            idRegistry.register(alice, address(0), url);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);
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
