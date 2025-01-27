// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {Guardians} from "../../../src/abstract/Guardians.sol";

contract GuardiansExample is Guardians {
    constructor(
        address owner
    ) Guardians(owner) {}
}

contract GuardiansSymTest is SymTest, Test {
    GuardiansExample guarded;
    address owner;
    address x;
    address y;

    function setUp() public {
        owner = address(0x1000);

        // Setup Guardians
        guarded = new GuardiansExample(owner);

        // Create symbolic addresses
        x = svm.createAddress("x");
        y = svm.createAddress("y");
    }

    function check_Invariants(bytes4 selector, address caller) public {
        _initState();
        vm.assume(x != owner);
        vm.assume(x != y);

        // Record pre-state
        bool oldPaused = guarded.paused();
        bool oldGuardianX = guarded.guardians(x);
        bool oldGuardianY = guarded.guardians(y);

        // Execute an arbitrary tx
        vm.prank(caller);
        (bool success,) = address(guarded).call(_calldataFor(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        bool newPaused = guarded.paused();
        bool newGuardianX = guarded.guardians(x);
        bool newGuardianY = guarded.guardians(y);

        // If the paused state is changed by any transaction...
        if (newPaused != oldPaused) {
            // If it wasn't paused before...
            if (!oldPaused) {
                // It must be paused now.
                assert(guarded.paused());

                // The function called was pause().
                assert(selector == guarded.pause.selector);

                // The caller must be the owner or a guardian.
                assert(caller == owner || guarded.guardians(caller));
            } // Otherwise, if it *was* paused before...
            else {
                // It must be unpaused now.
                assert(!guarded.paused());

                // The function called was unpause().
                assert(selector == guarded.unpause.selector);

                // The caller must be the owner.
                assert(caller == owner);
            }
        }

        // If X's guardian state is changed by any transaction...
        if (newGuardianX != oldGuardianX) {
            // The caller must be the owner.
            assert(caller == owner);

            // Y's guardian state must not be changed.
            assert(newGuardianY == oldGuardianY);
        }

        // If Y's guardian state is changed by any transaction...
        if (newGuardianY != oldGuardianY) {
            // The caller must be the owner.
            assert(caller == owner);

            // X's guardian state must not be changed.
            assert(newGuardianX == oldGuardianX);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initialize IdRegistry with symbolic arguments for state.
     */
    function _initState() public {
        if (svm.createBool("pause?")) {
            vm.prank(owner);
            guarded.pause();
        }
    }

    /**
     * @dev Generates valid calldata for a given function selector.
     */
    function _calldataFor(
        bytes4 selector
    ) internal returns (bytes memory) {
        return abi.encodePacked(selector, svm.createBytes(1024, "data"));
    }
}
