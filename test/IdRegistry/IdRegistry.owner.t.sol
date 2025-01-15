// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IdRegistry} from "../../src/IdRegistry.sol";
import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";
import {IGuardians} from "../../src/abstract/Guardians.sol";

/* solhint-disable state-visibility */

contract IdRegistryOwnerTest is IdRegistryTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Add(address indexed guardian);
    event Remove(address indexed guardian);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

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

    function testFuzzAcceptOwnership(
        address newOwner
    ) public {
        vm.assume(newOwner != owner && newOwner != address(0));
        vm.prank(owner);
        idRegistry.transferOwnership(newOwner);

        vm.expectEmit();
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
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    function testPause() public {
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.paused(), false);

        _pause();
    }

    function testAddRemoveGuardian(
        address guardian
    ) public {
        assertEq(idRegistry.guardians(guardian), false);

        vm.expectEmit();
        emit Add(guardian);

        vm.prank(owner);
        idRegistry.addGuardian(guardian);

        assertEq(idRegistry.guardians(guardian), true);

        vm.expectEmit();
        emit Remove(guardian);

        vm.prank(owner);
        idRegistry.removeGuardian(guardian);

        assertEq(idRegistry.guardians(guardian), false);
    }

    function testFuzzCannotPauseUnlessGuardian(
        address alice
    ) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idRegistry.owner(), owner);
        assertEq(idRegistry.paused(), false);

        vm.prank(alice);
        vm.expectRevert(IGuardians.OnlyGuardian.selector);
        idRegistry.pause();

        assertEq(idRegistry.paused(), false);
    }

    function testUnpause() public {
        _pause();

        vm.prank(owner);
        idRegistry.unpause();

        assertEq(idRegistry.paused(), false);
    }

    function testFuzzCannotUnpauseUnlessOwner(
        address alice
    ) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idRegistry.owner(), owner);
        _pause();

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.unpause();

        assertEq(idRegistry.paused(), true);
    }

    function testCannotAddGuardianUnlessOwner(address caller, address guardian) public {
        vm.assume(caller != owner);
        assertEq(idRegistry.guardians(guardian), false);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.addGuardian(guardian);

        assertEq(idRegistry.guardians(guardian), false);
    }

    function testCannotRemoveGuardianUnlessOwner(address caller, address guardian) public {
        vm.assume(caller != owner);
        assertEq(idRegistry.guardians(guardian), false);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        idRegistry.addGuardian(guardian);

        assertEq(idRegistry.guardians(guardian), false);
    }
}
