// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {IDRegistryTestable} from "./Utils.sol";

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
        idRegistry.disableTrustedRegister();

        for (uint256 i = 0; i < 25; i++) {
            uint256 idx = i + 1;
            address alice = address(uint160(idx));

            idRegistry.register(alice, address(0), url);
            assertEq(idRegistry.idOf(alice), idx);
        }
    }

    function testGasRegisterFromTrustedSender() public {
        idRegistry.setTrustedSender(TRUSTED_SENDER);

        for (uint256 i = 0; i < 25; i++) {
            uint256 idx = i + 1;
            address alice = address(uint160(idx));

            vm.prank(TRUSTED_SENDER);
            idRegistry.trustedRegister(alice, address(0), url);
            assertEq(idRegistry.idOf(alice), idx);
        }
    }
}
