// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../TestConstants.sol";

import {IdRegistry} from "../../src/IdRegistry.sol";
import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract IdRegistryTest is IdRegistryTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(address alice, address bob, address recovery) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        assertEq(idRegistry.getIdCounter(), 0);

        idRegistry.disableTrustedOnly();

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Register(bob, 1, recovery);
        idRegistry.register(bob, recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(bob), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotRegisterIfSeedable(address alice, address bob, address recovery) public {
        vm.assume(alice != FORWARDER && recovery != FORWARDER);
        assertEq(idRegistry.getIdCounter(), 0);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.Seedable.selector);
        idRegistry.register(bob, recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(bob), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterToAnAddressThatOwnsAnId(address alice, address bob, address recovery) public {
        vm.assume(alice != FORWARDER);
        _register(alice);
        assertEq(idRegistry.getIdCounter(), 1);

        vm.prank(bob);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.register(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedRegister(address alice, address trustedCaller, address recovery) public {
        vm.assume(trustedCaller != FORWARDER && trustedCaller != address(0));
        vm.assume(recovery != FORWARDER);
        idRegistry.changeTrustedCaller(trustedCaller);
        assertEq(idRegistry.getIdCounter(), 0);

        vm.prank(trustedCaller);
        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, recovery);
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotTrustedRegisterUnlessTrustedCallerOnly(
        address alice,
        address trustedCaller,
        address recovery
    ) public {
        vm.assume(trustedCaller != FORWARDER && recovery != FORWARDER);
        idRegistry.disableTrustedOnly();

        vm.prank(trustedCaller);
        vm.expectRevert(IdRegistry.Registrable.selector);
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterFromUntrustedCaller(
        address alice,
        address trustedCaller,
        address untrustedCaller,
        address recovery
    ) public {
        vm.assume(untrustedCaller != FORWARDER && recovery != FORWARDER);
        vm.assume(untrustedCaller != trustedCaller);
        vm.assume(trustedCaller != address(0));
        idRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(untrustedCaller);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterToAnAddressThatOwnsAnID(
        address alice,
        address trustedCaller,
        address recovery
    ) public {
        vm.assume(trustedCaller != FORWARDER && trustedCaller != address(0));
        idRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        idRegistry.trustedRegister(alice, address(0));
        assertEq(idRegistry.getIdCounter(), 1);

        vm.prank(trustedCaller);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransfer(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != bob);
        _register(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);
    }

    function testFuzzTransferDoesntResetRecoveryState(
        address alice,
        address bob,
        address recovery,
        address recoveryDestination
    ) public {
        vm.assume(alice != FORWARDER && alice != bob && alice != recoveryDestination);
        vm.assume(recovery != FORWARDER);

        _registerWithRecovery(alice, recovery);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotTransferToAddressWithId(address alice, address bob, address recovery) public {
        vm.assume(alice != FORWARDER && alice != bob);
        vm.assume(bob != FORWARDER);
        _registerWithRecovery(alice, recovery);
        _registerWithRecovery(bob, recovery);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 2);
    }

    function testFuzzCannotTransferIfNoId(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 0);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 0);
    }

    function testFuzzTransferReregister(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != bob);
        _register(alice);

        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.idOf(bob), 0);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        idRegistry.transfer(bob);

        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.idOf(bob), 1);

        _register(alice);
        assertEq(idRegistry.idOf(alice), 2);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeRecoveryAddress(address alice, address oldRecovery, address newRecovery) public {
        vm.assume(alice != FORWARDER);
        _registerWithRecovery(alice, oldRecovery);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ChangeRecoveryAddress(1, newRecovery);
        idRegistry.changeRecoveryAddress(newRecovery);

        assertEq(idRegistry.getRecoveryOf(1), newRecovery);
    }

    function testFuzzCannotChangeRecoveryAddressWithoutId(address alice, address bob) public {
        vm.assume(alice != FORWARDER && bob != FORWARDER);
        vm.assume(alice != bob);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.changeRecoveryAddress(bob);
    }

    /*//////////////////////////////////////////////////////////////
                            RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRecover(address from, address to, address recovery) public {
        vm.assume(from != FORWARDER && recovery != FORWARDER);
        vm.assume(from != to);

        _registerWithRecovery(from, recovery);

        vm.prank(recovery);
        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);
        idRegistry.recover(from, to);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotRecoverWithoutId(address from, address recovery, address to) public {
        vm.assume(from != FORWARDER && recovery != FORWARDER);
        vm.assume(from != to);
        vm.assume(recovery != address(0));

        vm.prank(recovery);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.recover(from, to);
    }

    function testFuzzCannotRecoverUnlessRecoveryAddress(
        address from,
        address to,
        address recovery,
        address notRecovery
    ) public {
        vm.assume(from != FORWARDER && recovery != FORWARDER && notRecovery != FORWARDER);
        vm.assume(recovery != notRecovery && from != notRecovery);
        vm.assume(from != to);

        _registerWithRecovery(from, recovery);

        vm.prank(notRecovery);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.recover(from, to);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotRecoverToAddressThatOwnsAnId(address from, address to, address recovery) public {
        vm.assume(from != FORWARDER && recovery != FORWARDER && to != FORWARDER);
        vm.assume(from != to);
        _registerWithRecovery(from, recovery);
        _register(to);

        vm.prank(recovery);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.recover(from, to);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }
}
