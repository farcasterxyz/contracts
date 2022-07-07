// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/AccountRegistry.sol";

contract AccountRegistryTest is Test {
    AccountRegistry accountRegistry;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(uint256 indexed id, address indexed to);

    event Transfer(uint256 indexed id, address indexed to);

    event SetRecoveryAddress(address indexed recovery, uint256 indexed id);

    event RequestRecovery(uint256 indexed id, address indexed from, address indexed to);

    event CancelRecovery(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        accountRegistry = new AccountRegistry();
    }

    address alice = address(0x123);
    address bob = address(0x456);
    address charlie = address(0x789);
    uint256 escrowPeriod = 20_000;

    /*//////////////////////////////////////////////////////////////
                       REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister() public {
        // 1. alice registers and claims id 1
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Register(1, alice);
        accountRegistry.register();
        assertEq(accountRegistry.idOf(alice), 1);

        // 2. bob registers after alice and claims id 2
        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit Register(2, bob);
        accountRegistry.register();
        assertEq(accountRegistry.idOf(bob), 2);
    }

    function testCannotRegisterTwice() public {
        // 1. alice reigsters and claims id 1
        vm.startPrank(alice);
        accountRegistry.register();

        // 2. alice attempts to register again and fails
        vm.expectRevert(CustodyAddressInvalid.selector);
        accountRegistry.register();
        vm.stopPrank();

        assertEq(accountRegistry.idOf(alice), 1);
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransfer() public {
        // 1. alice registers the first account and claims id 1
        vm.startPrank(alice);
        accountRegistry.register();
        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(bob), 0);

        // 2. alice transfers the id to bob
        vm.expectEmit(true, true, false, true);
        emit Transfer(1, bob);
        accountRegistry.transfer(bob);

        assertEq(accountRegistry.idOf(alice), 0);
        assertEq(accountRegistry.idOf(bob), 1);
    }

    function testCannotTransferToAddressWithId() public {
        // 1. alice and bob claim id's 1 and 2
        vm.prank(alice);
        accountRegistry.register();
        vm.prank(bob);
        accountRegistry.register();

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(bob), 2);

        // 2. alice tries to transfer id to bob's address
        vm.prank(alice);
        vm.expectRevert(CustodyAddressInvalid.selector);
        accountRegistry.transfer(bob);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(bob), 2);
    }

    function testCannotTransferIfNoId() public {
        // 1. alice tries to transfer an id to bob
        vm.prank(alice);
        vm.expectRevert(IdInvalid.selector);
        accountRegistry.transfer(bob);

        assertEq(accountRegistry.idOf(alice), 0);
        assertEq(accountRegistry.idOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SET RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetRecoveryAddress() public {
        // 1. alice registers id 1
        vm.startPrank(alice);
        accountRegistry.register();

        // 2. alice sets bob as her recovery address
        vm.expectEmit(true, true, false, true);
        emit SetRecoveryAddress(bob, 1);
        accountRegistry.setRecoveryAddress(bob);

        assertEq(accountRegistry.recoveryOf(1), bob);

        // 3. alice sets charlie as her recovery address
        vm.expectEmit(true, true, false, true);
        emit SetRecoveryAddress(charlie, 1);
        accountRegistry.setRecoveryAddress(charlie);
        vm.stopPrank();

        assertEq(accountRegistry.recoveryOf(1), charlie);
    }

    function testCannotSetSelfAsRecovery() public {
        // 1. alice registers id 1
        vm.startPrank(alice);
        accountRegistry.register();

        // 2. alice sets herself as the recovery address, which fails
        vm.expectRevert(RecoveryAddressInvalid.selector);
        accountRegistry.setRecoveryAddress(alice);
        vm.stopPrank();

        assertEq(accountRegistry.recoveryOf(1), address(0));
    }

    function testCannotSetRecoveryAddressWithoutId() public {
        vm.startPrank(alice);
        vm.expectRevert(IdInvalid.selector);
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        assertEq(accountRegistry.recoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(1, alice, charlie);
        accountRegistry.requestRecovery(alice, charlie);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.recoveryOf(1), bob);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryClockOf(1), block.number);
        assertEq(accountRegistry.recoveryDestinationOf(1), charlie);
    }

    function testCannotRequestRecoveryUnlessAuthorized() public {
        // 1. alice registers t id 1
        vm.prank(alice);
        accountRegistry.register();

        // 2. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        accountRegistry.requestRecovery(alice, charlie);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
    }

    function testCannotRequestRecoveryToAddressThatOwnsAnId() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. charlie registers id 2
        vm.prank(charlie);
        accountRegistry.register();

        // 3. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        vm.expectRevert(CustodyAddressInvalid.selector);
        accountRegistry.requestRecovery(alice, charlie);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 2);
    }

    function testCannotRequestRecoveryUnlessIssued() public {
        // 1. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        accountRegistry.requestRecovery(alice, bob);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRecoveryCompletion() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        accountRegistry.requestRecovery(alice, charlie);

        // 3. after escrow period, bob completes the recovery to charlie
        vm.roll(block.number + escrowPeriod);
        vm.expectEmit(true, true, false, true);
        emit Transfer(1, charlie);
        accountRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(accountRegistry.idOf(alice), 0);
        assertEq(accountRegistry.idOf(charlie), 1);
        assertEq(accountRegistry.recoveryOf(1), address(0));
        assertEq(accountRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCompleteRecoveryIfUnauthorized() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        uint256 requestBlock = block.number;
        vm.prank(bob);
        accountRegistry.requestRecovery(alice, charlie);

        // 3. charlie calls completeRecovery on alice's id, which fails
        vm.prank(charlie);
        vm.roll(requestBlock + escrowPeriod);
        vm.expectRevert(Unauthorized.selector);
        accountRegistry.completeRecovery(alice);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);
        assertEq(accountRegistry.recoveryClockOf(1), requestBlock);
    }

    function testCannotCompleteRecoveryIfNotStarted() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob calls recovery complete on alice's id, which fails
        vm.startPrank(bob);
        vm.roll(block.number + escrowPeriod);
        vm.expectRevert(RecoveryNotFound.selector);
        accountRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);
        assertEq(accountRegistry.recoveryClockOf(1), 0);
    }

    // cannot complete a recovery if enough time hasn't passed
    function testCannotCompleteRecoveryWhenInEscrow() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        uint256 requestBlock = block.number;
        accountRegistry.requestRecovery(alice, charlie);

        // 3. before the escrow period, bob completes the recovery to charlie
        vm.expectRevert(RecoveryInEscrow.selector);
        accountRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);
        assertEq(accountRegistry.recoveryClockOf(1), requestBlock);
    }

    function testCannotCompleteRecoveryToAddressThatOwnsAnId() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        uint256 requestBlock = block.number;
        accountRegistry.requestRecovery(alice, charlie);

        // 3. charlie registers id 2
        vm.prank(charlie);
        accountRegistry.register();

        // 4. after escrow period, bob completes the recovery to charlie which fails
        vm.startPrank(bob);
        vm.roll(requestBlock + escrowPeriod);
        vm.expectRevert(CustodyAddressInvalid.selector);
        accountRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 2);
        assertEq(accountRegistry.recoveryOf(1), bob);
        assertEq(accountRegistry.recoveryClockOf(1), requestBlock);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress() public {
        // 1. alice registers id 1 and sets bob as her recovery
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        accountRegistry.requestRecovery(alice, charlie);

        // 3. alice cancels the recovery
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery(1);
        accountRegistry.cancelRecovery(alice);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.roll(block.number + escrowPeriod);
        vm.expectRevert(RecoveryNotFound.selector);
        vm.prank(bob);
        accountRegistry.completeRecovery(alice);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);
        assertEq(accountRegistry.recoveryClockOf(1), 0);
    }

    function testCancelRecoveryFromRecoveryAddress() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        accountRegistry.requestRecovery(alice, charlie);

        // 3. after 1 block, bob cancels the recovery
        vm.prank(bob);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery(1);
        accountRegistry.cancelRecovery(alice);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.roll(block.number + escrowPeriod);
        vm.expectRevert(RecoveryNotFound.selector);
        vm.prank(bob);
        accountRegistry.completeRecovery(alice);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);
        assertEq(accountRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCancelRecoveryIfNotStarted() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);

        // 2. alice cancels the recovery which fails
        vm.expectRevert(RecoveryNotFound.selector);
        accountRegistry.cancelRecovery(alice);
        vm.stopPrank();

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.recoveryClockOf(1), 0);
        assertEq(accountRegistry.recoveryOf(1), bob);
    }

    function testCannotCancelRecoveryIfUnauthorized() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        accountRegistry.register();
        accountRegistry.setRecoveryAddress(bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        accountRegistry.requestRecovery(alice, charlie);

        // 3. charlie cancels the recovery which fails
        vm.prank(charlie);
        vm.expectRevert(Unauthorized.selector);
        accountRegistry.cancelRecovery(alice);

        assertEq(accountRegistry.idOf(alice), 1);
        assertEq(accountRegistry.idOf(charlie), 0);
        assertEq(accountRegistry.recoveryClockOf(1), block.number);
        assertEq(accountRegistry.recoveryOf(1), bob);
    }
}
