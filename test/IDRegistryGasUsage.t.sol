// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {IDRegistryTestable} from "./Utils.sol";

/* solhint-disable state-visibility */

contract IDRegistryGasUsageTest is Test {
    IDRegistryTestable idRegistry;

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);

    function setUp() public {
        idRegistry = new IDRegistryTestable(FORWARDER);
    }

    function testGasRegister() public {
        idRegistry.disableTrustedRegister();
        for (uint256 i = 0; i < 25; i++) {
            vm.prank(address(uint160(i)));
            idRegistry.register(address(0));
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);
        }
    }

    function testGasRegisterWithOptions() public {
        string memory url = "https://farcaster.xyz";
        idRegistry.disableTrustedRegister();
        for (uint256 i = 0; i < 25; i++) {
            idRegistry.register(address(uint160(i)), address(0), url);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);
        }
    }

    function testGasRegisterFromTrustedSender() public {
        string memory url = "https://farcaster.xyz";
        idRegistry.setTrustedSender(address(500));

        for (uint256 i = 0; i < 25; i++) {
            vm.prank(address(500));
            idRegistry.trustedRegister(address(uint160(i)), address(0), url);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);
        }
    }
}
