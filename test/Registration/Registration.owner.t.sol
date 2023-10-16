// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Registration} from "../../src/Registration.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {RegistrationTestSuite} from "./RegistrationTestSuite.sol";

/* solhint-disable state-visibility */

contract RegistrationOwnerTest is RegistrationTestSuite {
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
        assertEq(registration.owner(), owner);

        vm.prank(owner);
        vm.expectEmit();
        emit SetTrustedCaller(address(0), alice, owner);
        registration.setTrustedCaller(alice);
        assertEq(registration.trustedCaller(), alice);
    }

    function testFuzzCannotSetTrustedCallerToZeroAddr() public {
        assertEq(registration.owner(), owner);

        vm.prank(owner);
        vm.expectRevert(TrustedCaller.InvalidAddress.selector);
        registration.setTrustedCaller(address(0));

        assertEq(registration.trustedCaller(), address(0));
    }

    function testFuzzCannotSetTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(bob != address(0));
        vm.assume(registration.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registration.setTrustedCaller(bob);
        assertEq(registration.trustedCaller(), address(0));
    }

    function testDisableTrustedCaller() public {
        assertEq(registration.owner(), owner);
        assertEq(registration.trustedOnly(), 1);

        vm.prank(owner);
        vm.expectEmit();
        emit DisableTrustedOnly();
        registration.disableTrustedOnly();
        assertEq(registration.trustedOnly(), 0);
    }

    function testFuzzCannotDisableTrustedCallerUnlessOwner(address alice) public {
        vm.assume(alice != address(0));
        vm.assume(registration.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registration.disableTrustedOnly();
        assertEq(registration.trustedOnly(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferOwnership(address newOwner, address newOwner2) public {
        vm.assume(newOwner != address(0) && newOwner2 != address(0));
        assertEq(registration.owner(), owner);
        assertEq(registration.pendingOwner(), address(0));

        vm.prank(owner);
        registration.transferOwnership(newOwner);
        assertEq(registration.owner(), owner);
        assertEq(registration.pendingOwner(), newOwner);

        vm.prank(owner);
        registration.transferOwnership(newOwner2);
        assertEq(registration.owner(), owner);
        assertEq(registration.pendingOwner(), newOwner2);
    }

    function testFuzzCannotTransferOwnershipUnlessOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && newOwner != address(0));
        assertEq(registration.owner(), owner);
        assertEq(registration.pendingOwner(), address(0));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registration.transferOwnership(newOwner);

        assertEq(registration.owner(), owner);
        assertEq(registration.pendingOwner(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzAcceptOwnership(address newOwner) public {
        vm.assume(newOwner != owner && newOwner != address(0));
        vm.prank(owner);
        registration.transferOwnership(newOwner);

        vm.expectEmit();
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        registration.acceptOwnership();

        assertEq(registration.owner(), newOwner);
        assertEq(registration.pendingOwner(), address(0));
    }

    function testFuzzCannotAcceptOwnershipUnlessPendingOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && alice != address(0));
        vm.assume(newOwner != alice && newOwner != address(0));

        vm.prank(owner);
        registration.transferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        registration.acceptOwnership();

        assertEq(registration.owner(), owner);
        assertEq(registration.pendingOwner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    function testPause() public {
        assertEq(registration.owner(), owner);
        assertEq(registration.paused(), false);

        vm.prank(registration.owner());
        registration.pause();
        assertEq(registration.paused(), true);
    }

    function testFuzzCannotPauseUnlessOwner(address alice) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(registration.owner(), owner);
        assertEq(registration.paused(), false);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registration.pause();

        assertEq(registration.paused(), false);
    }

    function testUnpause() public {
        vm.prank(registration.owner());
        registration.pause();
        assertEq(registration.paused(), true);

        vm.prank(owner);
        registration.unpause();

        assertEq(registration.paused(), false);
    }

    function testFuzzCannotUnpauseUnlessOwner(address alice) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(registration.owner(), owner);

        vm.prank(registration.owner());
        registration.pause();
        assertEq(registration.paused(), true);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registration.unpause();

        assertEq(registration.paused(), true);
    }
}
