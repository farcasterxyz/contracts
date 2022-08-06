// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import {IDRegistry} from "../src/IDRegistry.sol";

/* solhint-disable state-visibility */

contract IDRegistryTest is Test {
    IDRegistry idRegistry;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event ChangeRecoveryAddress(address indexed recovery, uint256 indexed id);

    event RequestRecovery(uint256 indexed id, address indexed from, address indexed to);

    event CancelRecovery(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    address alice = address(0x123);
    address bob = address(0x456);
    address charlie = address(0x789);
    address zeroAddress = address(0);
    address trustedForwarder = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);

    uint256 escrowPeriod = 259_200;

    function setUp() public {
        idRegistry = new IDRegistry(trustedForwarder);
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister() public {
        // 1. alice registers id 1 and does not configure a recovery address
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, zeroAddress);
        idRegistry.register(zeroAddress);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryOf(1), zeroAddress);

        // 2. bob registers id 2 after alice and sets charlie a recovery address
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Register(bob, 2, charlie);
        idRegistry.register(charlie);

        assertEq(idRegistry.idOf(bob), 2);
        assertEq(idRegistry.recoveryOf(2), charlie);
    }

    function testCannotRegisterTwice() public {
        // 1. alice registers id 1
        vm.prank(alice);
        idRegistry.register(zeroAddress);

        // 2. alice attempts to register again and fails
        vm.prank(alice);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.register(zeroAddress);

        assertEq(idRegistry.idOf(alice), 1);
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransfer() public {
        // 1. alice registers the first account and claims id 1
        vm.prank(alice);
        idRegistry.register(zeroAddress);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);

        // 2. alice transfers the id to bob
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, 1);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);
    }

    function testCannotTransferToAddressWithId() public {
        // 1. alice and bob claim id's 1 and 2
        vm.prank(alice);
        idRegistry.register(zeroAddress);
        vm.prank(bob);
        idRegistry.register(zeroAddress);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);

        // 2. alice tries to transfer id to bob's address
        vm.prank(alice);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);
    }

    function testCannotTransferIfNoId() public {
        // 1. alice tries to transfer an id to bob
        vm.prank(alice);
        vm.expectRevert(IDRegistry.ZeroId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeRecoveryAddress() public {
        // 1. alice registers id 1
        vm.startPrank(alice);
        idRegistry.register(zeroAddress);

        // 2. alice sets bob as her recovery address
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(bob, 1);
        idRegistry.changeRecoveryAddress(bob);

        assertEq(idRegistry.recoveryOf(1), bob);

        // 3. alice sets charlie as her recovery address
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(charlie, 1);
        idRegistry.changeRecoveryAddress(charlie);
        vm.stopPrank();

        assertEq(idRegistry.recoveryOf(1), charlie);
    }

    function testCannotChangeRecoveryAddressWithoutId() public {
        vm.startPrank(alice);
        vm.expectRevert(IDRegistry.ZeroId.selector);
        idRegistry.changeRecoveryAddress(bob);
        vm.stopPrank();

        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(1, alice, charlie);
        idRegistry.requestRecovery(alice, charlie);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryClockOf(1), block.timestamp);
        assertEq(idRegistry.recoveryDestinationOf(1), charlie);
    }

    function testCannotRequestRecoveryUnlessAuthorized() public {
        // 1. alice registers t id 1
        vm.prank(alice);
        idRegistry.register(zeroAddress);

        // 2. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.requestRecovery(alice, charlie);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
    }

    function testCannotRequestRecoveryToAddressThatOwnsAnId() public {
        registerAlice();

        // 2. charlie registers id 2
        vm.prank(charlie);
        idRegistry.register(zeroAddress);

        // 3. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.requestRecovery(alice, charlie);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 2);
    }

    function testCannotRequestRecoveryUnlessIssued() public {
        // 1. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.requestRecovery(alice, bob);
    }

    /*//////////////////////////////////////////////////////////////
                         COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRecoveryCompletion() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. after escrow period, bob completes the recovery to charlie
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, charlie, 1);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(charlie), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCompleteRecoveryIfUnauthorized() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        uint256 requestBlock = block.timestamp;
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. charlie calls completeRecovery on alice's id, which fails
        vm.prank(charlie);
        vm.warp(requestBlock + escrowPeriod);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), requestBlock);
    }

    function testCannotCompleteRecoveryIfNotStarted() public {
        registerAlice();

        // 1. bob calls recovery complete on alice's id, which fails
        vm.startPrank(bob);
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    // cannot complete a recovery if enough time hasn't passed
    function testCannotCompleteRecoveryWhenInEscrow() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        uint256 requestBlock = block.timestamp;
        idRegistry.requestRecovery(alice, charlie);

        // 2. before the escrow period, bob completes the recovery to charlie
        vm.expectRevert(IDRegistry.Escrow.selector);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), requestBlock);
    }

    function testCannotCompleteRecoveryToAddressThatOwnsAnId() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        uint256 requestBlock = block.timestamp;
        idRegistry.requestRecovery(alice, charlie);

        // 2. charlie registers id 2
        vm.prank(charlie);
        idRegistry.register(zeroAddress);

        // 3. after escrow period, bob completes the recovery to charlie which fails
        vm.startPrank(bob);
        vm.warp(requestBlock + escrowPeriod);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 2);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), requestBlock);
    }

    /*//////////////////////////////////////////////////////////////
                          CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. alice cancels the recovery
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery(1);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);

        // 3. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        vm.prank(bob);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCancelRecoveryFromRecoveryAddress() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. after 1 block, bob cancels the recovery
        vm.prank(bob);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery(1);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);

        // 3. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        vm.prank(bob);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCancelRecoveryIfNotStarted() public {
        registerAlice();

        // 1. alice cancels the recovery which fails
        vm.prank(alice);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryClockOf(1), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
    }

    function testCannotCancelRecoveryIfUnauthorized() public {
        registerAlice();

        // 1. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. charlie cancels the recovery which fails
        vm.prank(charlie);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryClockOf(1), block.timestamp);
        assertEq(idRegistry.recoveryOf(1), bob);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function registerAlice() internal {
        vm.startPrank(alice);
        idRegistry.register(zeroAddress);
        idRegistry.changeRecoveryAddress(bob);
        vm.stopPrank();
    }
}
