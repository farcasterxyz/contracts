// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "./TestConstants.sol";

import {IdRegistry} from "../src/IdRegistry.sol";
import {IdRegistryTestable} from "./Utils.sol";

/* solhint-disable state-visibility */

contract IdRegistryTest is Test {
    IdRegistryTestable idRegistry;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery, string url);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ChangeHome(uint256 indexed id, string url);
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed id);
    event CancelRecovery(address indexed by, uint256 indexed id);
    event ChangeTrustedCaller(address indexed trustedCaller);
    event DisableTrustedOnly();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    uint256 constant ESCROW_PERIOD = 259_200;
    address owner = address(this);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        idRegistry = new IdRegistryTestable(FORWARDER);
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister(address alice, address bob, address recovery, string calldata url) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        assertEq(idRegistry.getIdCounter(), 0);

        idRegistry.disableTrustedOnly();

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Register(bob, 1, recovery, url);
        idRegistry.register(bob, recovery, url);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(bob), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testCannotRegisterIfTrustedCallerOnly(
        address alice,
        address bob,
        address recovery,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        assertEq(idRegistry.getIdCounter(), 0);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.Invitable.selector);
        idRegistry.register(bob, recovery, url);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testCannotRegisterToAnAddressThatOwnsAnID(
        address alice,
        address bob,
        address recovery,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER);
        _register(alice, address(0));
        assertEq(idRegistry.getIdCounter(), 1);

        vm.prank(bob);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.register(alice, recovery, url);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTrustedRegister(address alice, address trustedCaller, address recovery, string calldata url) public {
        vm.assume(trustedCaller != FORWARDER && recovery != FORWARDER);
        idRegistry.changeTrustedCaller(trustedCaller);
        assertEq(idRegistry.getIdCounter(), 0);

        vm.prank(trustedCaller);
        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, recovery, url);
        idRegistry.trustedRegister(alice, recovery, url);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testCannotTrustedRegisterUnlessTrustedCallerOnly(
        address alice,
        address trustedCaller,
        address recovery,
        string calldata url
    ) public {
        vm.assume(trustedCaller != FORWARDER && recovery != FORWARDER);
        idRegistry.disableTrustedOnly();

        vm.prank(trustedCaller);
        vm.expectRevert(IdRegistry.Registrable.selector);
        idRegistry.trustedRegister(alice, recovery, url);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testCannotTrustedRegisterFromUntrustedCaller(
        address alice,
        address trustedCaller,
        address untrustedCaller,
        address recovery,
        string calldata url
    ) public {
        vm.assume(untrustedCaller != FORWARDER && recovery != FORWARDER);
        vm.assume(untrustedCaller != trustedCaller);
        idRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(untrustedCaller);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.trustedRegister(alice, recovery, url);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testCannotTrustedRegisterToAnAddressThatOwnsAnID(
        address alice,
        address trustedCaller,
        address recovery,
        string calldata url
    ) public {
        vm.assume(trustedCaller != FORWARDER);
        idRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        idRegistry.trustedRegister(alice, address(0), url);
        assertEq(idRegistry.getIdCounter(), 1);

        vm.prank(trustedCaller);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.trustedRegister(alice, recovery, url);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                               HOME TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeHome(address alice, address recovery, string calldata url) public {
        vm.assume(alice != FORWARDER);
        _register(alice, recovery);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ChangeHome(1, url);
        idRegistry.changeHome(url);
    }

    function testCannotChangeHomeWithoutId(address alice, string calldata url) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.changeHome(url);
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransfer(address alice, address bob) public {
        vm.assume(alice != FORWARDER);
        vm.assume(alice != bob);
        _register(alice, address(0));

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);
    }

    function testTransferResetsRecoveryState(
        address alice,
        address bob,
        address recovery,
        address recoveryTarget
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        vm.assume(alice != bob);
        vm.assume(alice != recoveryTarget);

        _register(alice, recovery);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);

        // request a recovery to set the clock to 1
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, recoveryTarget);
        assertEq(idRegistry.getRecoveryClockOf(1), 1);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
    }

    function testCannotTransferToAddressWithId(address alice, address bob, address recovery) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        _register(alice, recovery);
        _register(bob, recovery);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);
    }

    function testCannotTransferIfNoId(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 0);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeRecoveryAddress(address alice, address oldRecovery, address newRecovery) public {
        vm.assume(alice != FORWARDER);
        _register(alice, oldRecovery);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(1, newRecovery);
        idRegistry.changeRecoveryAddress(newRecovery);

        assertEq(idRegistry.getRecoveryOf(1), newRecovery);
    }

    function testChangeRecoveryAddressResetsRecovery(
        address alice,
        address oldRecovery,
        address recoveryTarget,
        address newRecovery
    ) public {
        vm.assume(alice != FORWARDER && oldRecovery != FORWARDER);
        vm.assume(alice != oldRecovery && alice != recoveryTarget);
        _register(alice, oldRecovery);

        vm.prank(oldRecovery);
        idRegistry.requestRecovery(alice, recoveryTarget);
        assertEq(idRegistry.getRecoveryClockOf(1), 1);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(1, newRecovery);
        idRegistry.changeRecoveryAddress(newRecovery);

        assertEq(idRegistry.getRecoveryClockOf(1), 0);
    }

    function testCannotChangeRecoveryAddressWithoutId(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.changeRecoveryAddress(bob);
    }

    /*//////////////////////////////////////////////////////////////
                         REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery(address alice, address bob, address recovery) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        _register(alice, recovery);
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
        assertEq(idRegistry.getRecoveryDestinationOf(1), address(0));

        vm.prank(recovery);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(alice, bob, 1);
        idRegistry.requestRecovery(alice, bob);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryClockOf(1), block.timestamp);
        assertEq(idRegistry.getRecoveryDestinationOf(1), bob);
    }

    function testRequestRecoveryOverridesPreviousRecovery(
        address alice,
        address bob,
        address charlie,
        address recovery,
        uint256 delay
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        delay = delay % FUZZ_TIME_PERIOD;
        _register(alice, recovery);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);
        assertEq(idRegistry.getRecoveryClockOf(1), block.timestamp);
        assertEq(idRegistry.getRecoveryDestinationOf(1), bob);

        // Move forward in time and request another recovery
        vm.warp(delay);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, charlie);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryClockOf(1), block.timestamp);
        assertEq(idRegistry.getRecoveryDestinationOf(1), charlie);
    }

    function testCannotRequestRecoveryUnlessRecoveryAddress(
        address alice,
        address recovery,
        address notRecovery,
        address recoveryDestination
    ) public {
        vm.assume(alice != FORWARDER && notRecovery != FORWARDER);
        vm.assume(alice != recoveryDestination);
        vm.assume(notRecovery != recovery);
        _register(alice, recovery);

        assertEq(idRegistry.getRecoveryClockOf(1), 0);
        assertEq(idRegistry.getRecoveryDestinationOf(1), address(0));

        vm.prank(notRecovery);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.requestRecovery(alice, recoveryDestination);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
        assertEq(idRegistry.getRecoveryDestinationOf(1), address(0));
    }

    function testCannotRequestRecoveryWithoutId(address alice, address bob, address recoveryDestination) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != recoveryDestination);
        vm.assume(bob != address(0));

        vm.prank(bob);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.requestRecovery(alice, recoveryDestination);
    }

    /*//////////////////////////////////////////////////////////////
                         COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteRecovery(
        address alice,
        address bob,
        address recovery,
        uint256 timestamp,
        uint256 delay
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        vm.assume(alice != bob);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay > ESCROW_PERIOD);
        _register(alice, recovery);

        // Travel to an arbitrary time and then alice requests recovery of id 1 to bob
        vm.warp(timestamp);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);

        // Wait for the escrow period to complete and complete the recovery to bob
        vm.prank(recovery);
        vm.warp(timestamp + delay);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
    }

    function testCannotCompleteRecoveryUnlessRecoveryAddress(
        address alice,
        address bob,
        address recovery,
        address notRecovery,
        uint256 timestamp,
        uint256 delay
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER && notRecovery != FORWARDER);
        vm.assume(recovery != notRecovery && alice != notRecovery);
        vm.assume(alice != bob);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= ESCROW_PERIOD);
        _register(alice, recovery);

        // recovery requests a recovery of alice's id to bob
        vm.warp(timestamp);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);

        // reverts when notRecovery tries to complete the recovery request
        vm.warp(timestamp + delay);
        vm.prank(notRecovery);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryClockOf(1), timestamp);
    }

    function testCannotCompleteRecoveryIfNotRequested(address alice, address recovery, uint256 delay) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        vm.assume(alice != recovery);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= ESCROW_PERIOD);
        _register(alice, recovery);

        vm.warp(block.timestamp + delay);
        vm.prank(recovery);
        vm.expectRevert(IdRegistry.NoRecovery.selector);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
    }

    function testCannotCompleteRecoveryWhenInEscrow(
        address alice,
        address bob,
        address recovery,
        uint256 timestamp,
        uint256 delay
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        vm.assume(alice != bob);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        delay = delay % ESCROW_PERIOD;
        _register(alice, recovery);

        // recovery requests a recovery of alice's id to bob
        vm.warp(timestamp);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);

        // fast forward to a time before the escrow period ends and try to complete
        vm.warp(timestamp + delay);
        vm.prank(recovery);
        vm.expectRevert(IdRegistry.Escrow.selector);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryClockOf(1), timestamp);
    }

    function testCannotCompleteRecoveryToAddressThatOwnsAnId(
        address alice,
        address bob,
        address recovery,
        uint256 timestamp,
        uint256 delay
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= ESCROW_PERIOD);
        _register(alice, recovery);
        _register(bob, recovery);

        // request a recovery of alice's fid to bob
        vm.warp(timestamp);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);

        // fast forward past the escrow period and try to complete the recovery, which fails
        vm.startPrank(recovery);
        vm.warp(timestamp + delay);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryClockOf(1), timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress(
        address alice,
        address bob,
        address recovery,
        uint256 timestamp,
        uint256 delay
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= ESCROW_PERIOD);
        _register(alice, recovery);

        // 1. recovery requests a recovery of alice's id to bob
        vm.warp(timestamp);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);

        // 2. alice cancels the recovery
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery(alice, 1);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        // 3. after escrow period, recovery tries to recover to bob and fails
        vm.warp(timestamp + delay);
        vm.expectRevert(IdRegistry.NoRecovery.selector);
        vm.prank(recovery);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
    }

    function testCancelRecoveryFromRecoveryAddress(
        address alice,
        address bob,
        address recovery,
        uint256 timestamp,
        uint256 delay
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= ESCROW_PERIOD);
        _register(alice, recovery);

        // 1. recovery requests a recovery of alice's id to bob
        vm.warp(timestamp);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);

        // 2. recovery cancels the recovery
        vm.prank(recovery);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery(recovery, 1);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        // 3. after escrow period, recovery tries to recover to bob and fails
        vm.warp(timestamp + delay);
        vm.expectRevert(IdRegistry.NoRecovery.selector);
        vm.prank(recovery);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
    }

    function testCannotCancelRecoveryIfNotStarted(address alice, address recovery) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        vm.assume(alice != recovery);
        _register(alice, recovery);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.NoRecovery.selector);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryClockOf(1), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testCannotCancelRecoveryIfUnauthorized(
        address alice,
        address bob,
        address unauthorized,
        address recovery,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER && unauthorized != FORWARDER);
        vm.assume(alice != bob);
        vm.assume(unauthorized != alice && unauthorized != recovery);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, recovery);

        // recovery requests a recovery of alice's id to bob
        vm.warp(timestamp);
        vm.prank(recovery);
        idRegistry.requestRecovery(alice, bob);

        // unauthorized cancels the recovery which fails
        vm.prank(unauthorized);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryClockOf(1), timestamp);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeTrustedCaller(address alice) public {
        vm.assume(alice != FORWARDER);
        assertEq(idRegistry.owner(), owner);

        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedCaller(alice);
        idRegistry.changeTrustedCaller(alice);
        assertEq(idRegistry.getTrustedCaller(), alice);
    }

    function testCannotChangeTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        vm.assume(idRegistry.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.changeTrustedCaller(bob);
        assertEq(idRegistry.getTrustedCaller(), address(0));
    }

    function testDisableTrustedCaller() public {
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getTrustedOnly(), 1);

        vm.expectEmit(true, true, true, true);
        idRegistry.disableTrustedOnly();
        emit DisableTrustedOnly();
        assertEq(idRegistry.getTrustedOnly(), 0);
    }

    function testCannotDisableTrustedCallerUnlessOwner(address alice) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        vm.assume(idRegistry.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.disableTrustedOnly();
        assertEq(idRegistry.getTrustedOnly(), 1);
    }

    function testCannotTransferOwnership(address newOwner) public {
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), address(0));

        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.transferOwnership(newOwner);

        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), address(0));
    }

    function testRequestTransferOwnership(address newOwner, address newOwner2) public {
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), address(0));

        idRegistry.requestTransferOwnership(newOwner);
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), newOwner);

        idRegistry.requestTransferOwnership(newOwner2);
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), newOwner2);
    }

    function testCannotRequestTransferOwnershipUnlessOwner(address alice, address newOwner) public {
        vm.assume(alice != FORWARDER && alice != owner);
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), address(0));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.requestTransferOwnership(newOwner);

        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), address(0));
    }

    function testCompleteTransferOwnership(address newOwner) public {
        vm.assume(newOwner != FORWARDER && newOwner != owner);
        vm.prank(owner);
        idRegistry.requestTransferOwnership(newOwner);

        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        idRegistry.completeTransferOwnership();

        assertEq(idRegistry.owner(), newOwner);
        assertEq(idRegistry.getPendingOwner(), address(0));
    }

    function testCannotCompleteTransferOwnershipUnlessPendingOwner(address alice, address newOwner) public {
        vm.assume(alice != FORWARDER && alice != owner && alice != address(0));
        vm.assume(newOwner != alice);

        vm.prank(owner);
        idRegistry.requestTransferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.completeTransferOwnership();

        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getPendingOwner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _register(address alice, address bob) internal {
        idRegistry.disableTrustedOnly();
        vm.prank(alice);
        idRegistry.register(alice, bob, "");
    }
}
