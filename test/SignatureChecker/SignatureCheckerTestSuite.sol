// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
/* solhint-disable state-visibility */

abstract contract SignatureCheckerTestSuite is TestSuiteSetup {
    uint256 constant SECP_256K1_ORDER = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    address admin = makeAddr("admin");

    function setUp() public override {
        super.setUp();
    }

    function _boundPk(uint256 pk) internal view returns (uint256) {
        return bound(pk, 1, SECP_256K1_ORDER - 1);
    }

    function _signMsg(uint256 pk, bytes32 digest) internal returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
