// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IdManager} from "../../src/IdManager.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {IdManagerTestSuite} from "./IdManagerTestSuite.sol";

/* solhint-disable state-visibility */

contract IdManagerOwnerTest is IdManagerTestSuite {
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
        assertEq(idManager.owner(), owner);

        vm.prank(owner);
        vm.expectEmit();
        emit SetTrustedCaller(address(0), alice, owner);
        idManager.setTrustedCaller(alice);
        assertEq(idManager.trustedCaller(), alice);
    }

    function testFuzzCannotSetTrustedCallerToZeroAddr() public {
        assertEq(idManager.owner(), owner);

        vm.prank(owner);
        vm.expectRevert(TrustedCaller.InvalidAddress.selector);
        idManager.setTrustedCaller(address(0));

        assertEq(idManager.trustedCaller(), address(0));
    }

    function testFuzzCannotSetTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(bob != address(0));
        vm.assume(idManager.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idManager.setTrustedCaller(bob);
        assertEq(idManager.trustedCaller(), address(0));
    }

    function testDisableTrustedCaller() public {
        assertEq(idManager.owner(), owner);
        assertEq(idManager.trustedOnly(), 1);

        vm.prank(owner);
        vm.expectEmit();
        emit DisableTrustedOnly();
        idManager.disableTrustedOnly();
        assertEq(idManager.trustedOnly(), 0);
    }

    function testFuzzCannotDisableTrustedCallerUnlessOwner(address alice) public {
        vm.assume(alice != address(0));
        vm.assume(idManager.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idManager.disableTrustedOnly();
        assertEq(idManager.trustedOnly(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferOwnership(address newOwner, address newOwner2) public {
        vm.assume(newOwner != address(0) && newOwner2 != address(0));
        assertEq(idManager.owner(), owner);
        assertEq(idManager.pendingOwner(), address(0));

        vm.prank(owner);
        idManager.transferOwnership(newOwner);
        assertEq(idManager.owner(), owner);
        assertEq(idManager.pendingOwner(), newOwner);

        vm.prank(owner);
        idManager.transferOwnership(newOwner2);
        assertEq(idManager.owner(), owner);
        assertEq(idManager.pendingOwner(), newOwner2);
    }

    function testFuzzCannotTransferOwnershipUnlessOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && newOwner != address(0));
        assertEq(idManager.owner(), owner);
        assertEq(idManager.pendingOwner(), address(0));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idManager.transferOwnership(newOwner);

        assertEq(idManager.owner(), owner);
        assertEq(idManager.pendingOwner(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzAcceptOwnership(address newOwner) public {
        vm.assume(newOwner != owner && newOwner != address(0));
        vm.prank(owner);
        idManager.transferOwnership(newOwner);

        vm.expectEmit();
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        idManager.acceptOwnership();

        assertEq(idManager.owner(), newOwner);
        assertEq(idManager.pendingOwner(), address(0));
    }

    function testFuzzCannotAcceptOwnershipUnlessPendingOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && alice != address(0));
        vm.assume(newOwner != alice && newOwner != address(0));

        vm.prank(owner);
        idManager.transferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        idManager.acceptOwnership();

        assertEq(idManager.owner(), owner);
        assertEq(idManager.pendingOwner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    function testPause() public {
        assertEq(idManager.owner(), owner);
        assertEq(idManager.paused(), false);

        vm.prank(idManager.owner());
        idManager.pause();
        assertEq(idManager.paused(), true);
    }

    function testFuzzCannotPauseUnlessOwner(address alice) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idManager.owner(), owner);
        assertEq(idManager.paused(), false);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idManager.pause();

        assertEq(idManager.paused(), false);
    }

    function testUnpause() public {
        vm.prank(idManager.owner());
        idManager.pause();
        assertEq(idManager.paused(), true);

        vm.prank(owner);
        idManager.unpause();

        assertEq(idManager.paused(), false);
    }

    function testFuzzCannotUnpauseUnlessOwner(address alice) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idManager.owner(), owner);

        vm.prank(idManager.owner());
        idManager.pause();
        assertEq(idManager.paused(), true);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idManager.unpause();

        assertEq(idManager.paused(), true);
    }
}
