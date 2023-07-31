// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IdRegistry} from "../../src/IdRegistry.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract IdRegistryOwnerTest is IdRegistryTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SetTrustedCaller(address indexed oldTrustedCaller, address indexed newTrustedCaller, address owner);
    event DisableTrustedOnly();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                             TRUSTED CALLER
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetTrustedCaller(address alice) public {
        vm.assume(alice != address(0));
        assertEq(idRegistry.owner(), owner);

        vm.prank(owner);
        vm.expectEmit();
        emit SetTrustedCaller(address(0), alice, owner);
        idRegistry.setTrustedCaller(alice);
        assertEq(idRegistry.trustedCaller(), alice);
    }

    function testFuzzCannotSetTrustedCallerToZeroAddr() public {
        assertEq(idRegistry.owner(), owner);

        vm.prank(owner);
        vm.expectRevert(TrustedCaller.InvalidAddress.selector);
        idRegistry.setTrustedCaller(address(0));

        assertEq(idRegistry.trustedCaller(), address(0));
    }

    function testFuzzCannotSetTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(bob != address(0));
        vm.assume(idRegistry.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.setTrustedCaller(bob);
        assertEq(idRegistry.trustedCaller(), address(0));
    }

    function testDisableTrustedCaller() public {
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.getTrustedOnly(), 1);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisableTrustedOnly();
        idRegistry.disableTrustedOnly();
        assertEq(idRegistry.getTrustedOnly(), 0);
    }

    function testFuzzCannotDisableTrustedCallerUnlessOwner(address alice) public {
        vm.assume(alice != address(0));
        vm.assume(idRegistry.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.disableTrustedOnly();
        assertEq(idRegistry.getTrustedOnly(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferOwnership(address newOwner, address newOwner2) public {
        vm.assume(newOwner != address(0) && newOwner2 != address(0));
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.pendingOwner(), address(0));

        vm.prank(owner);
        idRegistry.transferOwnership(newOwner);
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.pendingOwner(), newOwner);

        vm.prank(owner);
        idRegistry.transferOwnership(newOwner2);
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.pendingOwner(), newOwner2);
    }

    function testFuzzCannotTransferOwnershipUnlessOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && newOwner != address(0));
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.pendingOwner(), address(0));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.transferOwnership(newOwner);

        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.pendingOwner(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzAcceptOwnership(address newOwner) public {
        vm.assume(newOwner != owner && newOwner != address(0));
        vm.prank(owner);
        idRegistry.transferOwnership(newOwner);

        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        idRegistry.acceptOwnership();

        assertEq(idRegistry.owner(), newOwner);
        assertEq(idRegistry.pendingOwner(), address(0));
    }

    function testFuzzCannotAcceptOwnershipUnlessPendingOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && alice != address(0));
        vm.assume(newOwner != alice && newOwner != address(0));

        vm.prank(owner);
        idRegistry.transferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        idRegistry.acceptOwnership();

        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.pendingOwner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                           PAUSE REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function testPauseRegistration() public {
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.paused(), false);

        _pauseRegistrations();
    }

    function testFuzzCannotPauseRegistrationUnlessOwner(address alice) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.paused(), false);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.pauseRegistration();

        assertEq(idRegistry.paused(), false);
    }

    function testUnpauseRegistration() public {
        _pauseRegistrations();

        vm.prank(owner);
        idRegistry.unpauseRegistration();

        assertEq(idRegistry.paused(), false);
    }

    function testFuzzCannotUnpauseUnlessOwner(address alice) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idRegistry.owner(), owner);
        _pauseRegistrations();

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.unpauseRegistration();

        assertEq(idRegistry.paused(), true);
    }
}
