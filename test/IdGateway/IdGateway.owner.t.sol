// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IdGateway} from "../../src/IdGateway.sol";
import {IGuardians} from "../../src/abstract/Guardians.sol";
import {IdGatewayTestSuite} from "./IdGatewayTestSuite.sol";

/* solhint-disable state-visibility */

contract IdGatewayOwnerTest is IdGatewayTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                           TRANSFER OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferOwnership(address newOwner, address newOwner2) public {
        vm.assume(newOwner != address(0) && newOwner2 != address(0));
        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.pendingOwner(), address(0));

        vm.prank(owner);
        idGateway.transferOwnership(newOwner);
        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.pendingOwner(), newOwner);

        vm.prank(owner);
        idGateway.transferOwnership(newOwner2);
        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.pendingOwner(), newOwner2);
    }

    function testFuzzCannotTransferOwnershipUnlessOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && newOwner != address(0));
        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.pendingOwner(), address(0));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idGateway.transferOwnership(newOwner);

        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.pendingOwner(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzAcceptOwnership(
        address newOwner
    ) public {
        vm.assume(newOwner != owner && newOwner != address(0));
        vm.prank(owner);
        idGateway.transferOwnership(newOwner);

        vm.expectEmit();
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        idGateway.acceptOwnership();

        assertEq(idGateway.owner(), newOwner);
        assertEq(idGateway.pendingOwner(), address(0));
    }

    function testFuzzCannotAcceptOwnershipUnlessPendingOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && alice != address(0));
        vm.assume(newOwner != alice && newOwner != address(0));

        vm.prank(owner);
        idGateway.transferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        idGateway.acceptOwnership();

        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.pendingOwner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    function testPause() public {
        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.paused(), false);

        vm.prank(idGateway.owner());
        idGateway.pause();
        assertEq(idGateway.paused(), true);
    }

    function testFuzzCannotPauseUnlessGuardian(
        address alice
    ) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idGateway.owner(), owner);
        assertEq(idGateway.paused(), false);

        vm.prank(alice);
        vm.expectRevert(IGuardians.OnlyGuardian.selector);
        idGateway.pause();

        assertEq(idGateway.paused(), false);
    }

    function testUnpause() public {
        vm.prank(idGateway.owner());
        idGateway.pause();
        assertEq(idGateway.paused(), true);

        vm.prank(owner);
        idGateway.unpause();

        assertEq(idGateway.paused(), false);
    }

    function testFuzzCannotUnpauseUnlessOwner(
        address alice
    ) public {
        vm.assume(alice != owner && alice != address(0));
        assertEq(idGateway.owner(), owner);

        vm.prank(idGateway.owner());
        idGateway.pause();
        assertEq(idGateway.paused(), true);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        idGateway.unpause();

        assertEq(idGateway.paused(), true);
    }
}
