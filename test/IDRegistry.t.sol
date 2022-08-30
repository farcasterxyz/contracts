// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {IDRegistry} from "../src/IDRegistry.sol";
import {IDRegistryTestable} from "./Utils.sol";

/* solhint-disable state-visibility */

contract IDRegistryTest is Test {
    IDRegistryTestable idRegistry;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery, string url);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ChangeHome(uint256 indexed id, string url);
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed id);
    event CancelRecovery(uint256 indexed id);
    event ChangeTrustedSender(address indexed trustedSender);
    event DisableTrustedRegister();

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
        idRegistry = new IDRegistryTestable(FORWARDER);
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister(
        address alice,
        address bob,
        address recovery,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        vm.assume(alice != recovery);

        idRegistry.disableTrustedRegister();
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Register(bob, 1, recovery, url);
        idRegistry.register(bob, recovery, url);

        assertEq(idRegistry.idOf(bob), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testRegisterIncrementsIds(
        address alice,
        address bob,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        _register(alice, address(0));

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Register(bob, 2, address(0), url);
        idRegistry.register(bob, address(0), url);

        assertEq(idRegistry.idOf(bob), 2);
        assertEq(idRegistry.recoveryOf(2), address(0));
    }

    function testCannotRegisterWhenTrustedSenderEnabled(
        address alice,
        address bob,
        address recovery,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.register(bob, recovery, url);

        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testCannotRegisterTwice(address alice) public {
        vm.assume(alice != FORWARDER);
        _register(alice, address(0));

        vm.prank(alice);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.register(alice, address(0), "");

        assertEq(idRegistry.idOf(alice), 1);
    }

    function testRegisterFromTrustedSender(
        address alice,
        address bob,
        address recovery,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        idRegistry.changeTrustedSender(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Register(bob, 1, recovery, url);
        idRegistry.trustedRegister(bob, recovery, url);

        assertEq(idRegistry.idOf(bob), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testCannotRegisterFromTrustedSenderUnlessEnabled(
        address alice,
        address bob,
        address recovery,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        idRegistry.disableTrustedRegister();

        vm.prank(alice);
        vm.expectRevert(IDRegistry.Registrable.selector);
        idRegistry.trustedRegister(bob, recovery, url);

        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testCannotRegisterFromTrustedSenderUnlessSender(
        address alice,
        address bob,
        address charlie,
        address recovery,
        string calldata url
    ) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        vm.assume(alice != charlie);
        idRegistry.changeTrustedSender(charlie);

        vm.prank(alice);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.trustedRegister(bob, recovery, url);

        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testChangeHome(
        address alice,
        address recovery,
        string calldata url
    ) public {
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
        vm.expectRevert(IDRegistry.ZeroId.selector);
        idRegistry.changeHome(url);
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransfer(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != bob);
        _register(alice, address(0));
        assertEq(idRegistry.idOf(bob), 0);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);
    }

    function testCannotTransferToAddressWithId(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);

        _register(alice, address(0));
        _register(bob, address(0));

        vm.prank(alice);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);
    }

    function testCannotTransferIfNoId(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(IDRegistry.ZeroId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeRecoveryAddress(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        _register(alice, address(0));
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(1, bob);
        idRegistry.changeRecoveryAddress(bob);

        assertEq(idRegistry.recoveryOf(1), bob);
    }

    function testChangeRecoveryAddressResetsRecovery(
        address alice,
        address bob,
        address charlie,
        address david
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && david != FORWARDER);
        vm.assume(alice != bob && alice != charlie);
        _register(alice, bob);

        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        vm.prank(alice);
        idRegistry.changeRecoveryAddress(david);

        assertEq(idRegistry.recoveryOf(1), david);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCannotChangeRecoveryAddressWithoutId(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);

        vm.prank(alice);
        vm.expectRevert(IDRegistry.ZeroId.selector);
        idRegistry.changeRecoveryAddress(bob);

        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery(
        address alice,
        address bob,
        address charlie
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(alice != charlie);
        _register(alice, bob);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(alice, charlie, 1);
        idRegistry.requestRecovery(alice, charlie);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryClockOf(1), block.timestamp);
        assertEq(idRegistry.recoveryDestinationOf(1), charlie);
    }

    function testCannotRequestRecoveryUnlessAuthorized(
        address alice,
        address bob,
        address charlie
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(bob != address(0));
        _register(alice, address(0));

        vm.prank(bob);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.requestRecovery(alice, charlie);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryClockOf(1), 0);
        assertEq(idRegistry.recoveryDestinationOf(1), address(0));
    }

    function testCannotRequestRecoveryToAddressThatOwnsAnId(
        address alice,
        address bob,
        address charlie
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(alice != charlie);
        _register(alice, bob);
        _register(charlie, bob);

        vm.prank(bob);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.requestRecovery(alice, charlie);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 2);
        assertEq(idRegistry.recoveryClockOf(1), 0);
        assertEq(idRegistry.recoveryDestinationOf(1), address(0));
    }

    function testCannotRequestRecoveryUnlessIssued(
        address alice,
        address bob,
        address charlie
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(bob != address(0));

        vm.prank(bob);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.requestRecovery(alice, charlie);
    }

    /*//////////////////////////////////////////////////////////////
                         COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteRecovery(
        address alice,
        address bob,
        address charlie,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. warp ahead of zero so that we can assert that recoveryClockOf is reset correctly
        vm.warp(timestamp);

        // 2. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 3. after escrow period, bob completes the recovery to charlie
        vm.warp(timestamp + ESCROW_PERIOD);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, 1);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(charlie), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCompleteRecoveryIfUnauthorized(
        address alice,
        address bob,
        address charlie,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(bob != charlie && alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. bob requests a recovery of alice's id to charlie
        vm.warp(timestamp);
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. charlie calls completeRecovery on alice's id, which fails
        vm.warp(timestamp + ESCROW_PERIOD);
        vm.prank(charlie);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), timestamp);
    }

    function testCannotCompleteRecoveryIfStartedByPrevious(
        address alice,
        address bob,
        address charlie,
        address david,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && david != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. bob requests a recovery of alice's id to charlie, and then alice changes the recovery address to david
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);
        vm.prank(alice);
        idRegistry.changeRecoveryAddress(david);

        // 2. after escrow period, david attempts to complete the recovery which fails
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.prank(david);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), david);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCompleteRecoveryIfNotStarted(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        _register(alice, bob);

        // 1. bob calls recovery complete on alice's id, which fails
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.prank(bob);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCompleteRecoveryWhenInEscrow(
        address alice,
        address bob,
        address charlie,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. bob requests a recovery of alice's id to charlie
        vm.warp(timestamp);
        vm.startPrank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. before the escrow period ends, bob tried to complete the recovery to charlie
        vm.expectRevert(IDRegistry.Escrow.selector);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), timestamp);
    }

    function testCannotCompleteRecoveryToAddressThatOwnsAnId(
        address alice,
        address bob,
        address charlie,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. bob requests a recovery of alice's id to charlie
        vm.warp(timestamp);
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. charlie registers id 2
        vm.prank(charlie);
        idRegistry.register(charlie, address(0), "");

        // 3. after escrow period, bob completes the recovery to charlie which fails
        vm.startPrank(bob);
        vm.warp(timestamp + ESCROW_PERIOD);
        vm.expectRevert(IDRegistry.HasId.selector);
        idRegistry.completeRecovery(alice);
        vm.stopPrank();

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 2);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress(
        address alice,
        address bob,
        address charlie,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. bob requests a recovery of alice's id to charlie
        vm.warp(timestamp);
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
        vm.warp(timestamp + ESCROW_PERIOD);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        vm.prank(bob);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCancelRecoveryFromRecoveryAddress(
        address alice,
        address bob,
        address charlie,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. bob requests a recovery of alice's id to charlie
        vm.warp(timestamp);
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. bob cancels the recovery
        vm.prank(bob);
        vm.expectEmit(true, false, false, true);
        emit CancelRecovery(1);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);

        // 3. after escrow period, bob tries to recover to charlie and fails
        vm.warp(timestamp + ESCROW_PERIOD);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        vm.prank(bob);
        idRegistry.completeRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
        assertEq(idRegistry.recoveryClockOf(1), 0);
    }

    function testCannotCancelRecoveryIfNotStarted(
        address alice,
        address bob,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);
        _register(alice, bob);

        vm.warp(timestamp);
        vm.prank(alice);
        vm.expectRevert(IDRegistry.NoRecovery.selector);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryClockOf(1), 0);
        assertEq(idRegistry.recoveryOf(1), bob);
    }

    function testCannotCancelRecoveryIfUnauthorized(
        address alice,
        address bob,
        address charlie,
        uint256 timestamp
    ) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER && charlie != FORWARDER);
        vm.assume(bob != charlie && alice != charlie);
        vm.assume(timestamp > 0 && timestamp < type(uint256).max - ESCROW_PERIOD);
        _register(alice, bob);

        // 1. bob requests a recovery of alice's id to charlie
        vm.warp(timestamp);
        vm.prank(bob);
        idRegistry.requestRecovery(alice, charlie);

        // 2. charlie cancels the recovery which fails
        vm.prank(charlie);
        vm.expectRevert(IDRegistry.Unauthorized.selector);
        idRegistry.cancelRecovery(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(charlie), 0);
        assertEq(idRegistry.recoveryClockOf(1), timestamp);
        assertEq(idRegistry.recoveryOf(1), bob);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeTrustedSender(address alice) public {
        vm.assume(alice != FORWARDER);
        assertEq(idRegistry.owner(), owner);

        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedSender(alice);
        idRegistry.changeTrustedSender(alice);
        assertEq(idRegistry.trustedSender(), alice);
    }

    function testCannotChangeTrustedSenderUnlessOwner(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        vm.assume(idRegistry.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.changeTrustedSender(bob);
        assertEq(idRegistry.trustedSender(), address(0));
    }

    function testDisableTrustedSender() public {
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.trustedRegisterEnabled(), 1);

        vm.expectEmit(true, true, true, true);
        emit DisableTrustedRegister();
        idRegistry.disableTrustedRegister();
        assertEq(idRegistry.trustedRegisterEnabled(), 0);
    }

    function testCannotDisableTrustedSenderUnlessOwner(address alice) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        vm.assume(idRegistry.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.disableTrustedRegister();
        assertEq(idRegistry.trustedRegisterEnabled(), 1);
    }

    function testTransferOwnership(address alice) public {
        vm.assume(alice != FORWARDER && alice != address(0));

        idRegistry.transferOwnership(alice);
        assertEq(idRegistry.owner(), alice);
    }

    function testCannotTransferOwnershipUnlessOwner(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != address(0) && bob != address(0));
        vm.assume(alice != owner);
        assertEq(idRegistry.owner(), owner);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.transferOwnership(bob);
        assertEq(idRegistry.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _register(address alice, address bob) internal {
        idRegistry.disableTrustedRegister();
        vm.prank(alice);
        idRegistry.register(alice, bob, "");
    }
}
