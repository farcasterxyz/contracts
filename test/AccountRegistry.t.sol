// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/AccountRegistry.sol";

contract AccountRegistryTest is Test {
    AccountRegistry accountRegistry;

    event Register(uint256 indexed id, address indexed custodyAddress);

    function setUp() public {
        accountRegistry = new AccountRegistry();
    }

    function testRegistration() public {
        // The first registration is always id 1
        vm.prank(address(1));
        vm.expectEmit(true, true, false, false);
        emit Register(1, address(1));
        accountRegistry.register();
        assertEq(accountRegistry.custodyAddressToid(address(1)), 1);

        // Successive registrations should have incrementing ids of 2, 3, ...
        vm.prank(address(2));
        vm.expectEmit(true, true, false, false);
        emit Register(2, address(2));
        accountRegistry.register();
        assertEq(accountRegistry.custodyAddressToid(address(2)), 2);

        vm.prank(address(3));
        vm.expectEmit(true, true, false, false);
        emit Register(3, address(3));
        accountRegistry.register();
        assertEq(accountRegistry.custodyAddressToid(address(3)), 3);
    }

    function testCannotRegisterTwice() public {
        accountRegistry.register();
        assertEq(accountRegistry.custodyAddressToid(address(this)), 1);
        vm.expectRevert(AccountHasId.selector);
        accountRegistry.register();
    }
}
