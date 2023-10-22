// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {TrustedCaller} from "../../../src/lib/TrustedCaller.sol";

contract TrustedCallerExample is TrustedCaller {
    constructor(address _owner) TrustedCaller(_owner) {}

    function onlyCallableWhenTrusted() external onlyTrustedCaller {}
    function onlyCallableWhenUntrusted() external whenNotTrusted {}
}

contract TrustedCallerSymTest is SymTest, Test {
    TrustedCallerExample trusted;
    address owner;

    function setUp() public {
        owner = address(0x1000);

        // Setup TrustedCaller
        trusted = new TrustedCallerExample(owner);
    }

    function check_Invariants(bytes4 selector, address caller) public {
        // Record pre-state
        address oldTrustedCaller = trusted.trustedCaller();
        uint256 oldTrustedOnly = trusted.trustedOnly();

        // Execute an arbitrary tx
        vm.prank(caller);
        (bool success,) = address(trusted).call(_calldataFor(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        address newTrustedCaller = trusted.trustedCaller();
        uint256 newTrustedOnly = trusted.trustedOnly();

        // If the trusted state is changed by any transaction...
        if (newTrustedOnly != oldTrustedOnly) {
            // The previous state was trusted
            assert(oldTrustedOnly == 1);

            // The function called was disableTrustedOnly()
            assert(selector == trusted.disableTrustedOnly.selector);

            // The caller was the owner.
            assert(caller == owner);
        }

        // If the trustedCaller is changed by any transaction...
        if (newTrustedCaller != oldTrustedCaller) {
            // The function called was setTrustedCaller()
            assert(selector == trusted.setTrustedCaller.selector);
            // The caller was the owner.
            assert(caller == owner);
        }

        // If the call was protected by onlyTrustedCaller modifier...
        if (selector == trusted.onlyCallableWhenTrusted.selector) {
            // The trustedOnly state must be unchanged.
            assert(newTrustedOnly == oldTrustedOnly);
            // The trustedCaller must be unchanged.
            assert(newTrustedCaller == oldTrustedCaller);

            // The trustedOnly state must be 1.
            assert(newTrustedOnly == 1);

            // The caller was the trustedCaller.
            assert(caller == newTrustedCaller);
        }

        // If the call was protected by whenNotTrusted modifier...
        if (selector == trusted.onlyCallableWhenUntrusted.selector) {
            // The trustedOnly state must be unchanged.
            assert(newTrustedOnly == oldTrustedOnly);
            // The trustedOnly state must be 0.
            assert(newTrustedOnly == 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Generates valid calldata for a given function selector.
     */
    function _calldataFor(bytes4 selector) internal returns (bytes memory) {
        return abi.encodePacked(selector, svm.createBytes(1024, "data"));
    }
}
