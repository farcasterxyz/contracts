// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/AccountRegistry.sol";

contract AccountRegistryTest is Test {
    AccountRegistry accountRegistry;

    event Register(uint256 indexed id, address indexed custodyAddress);
    event SetRecovery(address indexed recovery, uint256 indexed id);

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

    function testSetRecovery() public {
        // register id i
        accountRegistry.register();

        // setRecovery and expect event and recovery to be populated
        vm.expectEmit(true, true, false, false);
        emit SetRecovery(address(10), 1);
        accountRegistry.setRecovery(1, address(10));
        assertEq(accountRegistry.idToRecoveryAddress(1), address(10));
    }

    function testCannotSetRecoveryToCustody() public {
        // register id i
        accountRegistry.register();

        // setRecovery and expect event and recovery to be populated
        vm.expectRevert(CustodyRecoveryDuplicate.selector);
        accountRegistry.setRecovery(1, address(this));
        assertEq(accountRegistry.idToRecoveryAddress(1), address(0));
    }

    function testCannotSetRecoveryUnlessOwner() public {
        // register id 1
        accountRegistry.register();

        // setRecovery for an unregistered id
        vm.expectRevert(AddressNotOwner.selector);
        accountRegistry.setRecovery(2, address(10));
        assertEq(accountRegistry.idToRecoveryAddress(2), address(0));

        // setRecovery for id 1 from an address that does not own it
        vm.prank(address(0));
        vm.expectRevert(AddressNotOwner.selector);
        accountRegistry.setRecovery(1, address(2));
        assertEq(accountRegistry.idToRecoveryAddress(1), address(0));
    }

    function testCannotSetRecoveryTwice() public {
        // register and setRecovery once
        accountRegistry.register();
        accountRegistry.setRecovery(1, address(10));
        assertEq(accountRegistry.idToRecoveryAddress(1), address(10));

        // setRecovery again and expect it to fail
        vm.expectRevert(AccountHasRecovery.selector);
        accountRegistry.setRecovery(1, address(11));
        assertEq(accountRegistry.idToRecoveryAddress(1), address(10));
    }

    function testCannotSetRecoveryForZeroId() public {
        accountRegistry.register();
        vm.expectRevert(InvalidId.selector);
        accountRegistry.setRecovery(0, address(10));
        assertEq(accountRegistry.idToRecoveryAddress(0), address(0));
    }
}
