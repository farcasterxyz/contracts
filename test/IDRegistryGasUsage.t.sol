// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {IDRegistry} from "../src/IDRegistry.sol";

/* solhint-disable state-visibility */

contract IDRegistryGasUsageTest is Test {
    IDRegistry idRegistry;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    address zeroAddress = address(0);
    address trustedForwarder = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);

    function setUp() public {
        idRegistry = new IDRegistry(trustedForwarder);
    }

    function testGasRegister() public {
        idRegistry.disableTrustedRegister();
        for (uint256 i = 0; i < 25; i++) {
            vm.prank(address(uint160(i)));
            idRegistry.register(zeroAddress);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);
        }
    }

    function testGasRegisterWithOptions(string calldata url) public {
        idRegistry.disableTrustedRegister();
        for (uint256 i = 0; i < 25; i++) {
            idRegistry.register(address(uint160(i)), zeroAddress, url);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);
        }
    }

    function testGasRegisterFromTrustedSender(string calldata url) public {
        idRegistry.setTrustedSender(address(500));

        for (uint256 i = 0; i < 25; i++) {
            vm.prank(address(500));
            idRegistry.trustedRegister(address(uint160(i)), zeroAddress, url);
            assertEq(idRegistry.idOf(address(uint160(i))), i + 1);
        }
    }
}
