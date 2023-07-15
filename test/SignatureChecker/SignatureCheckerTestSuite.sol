// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IdRegistryTestSuite} from "../IdRegistry/IdRegistryTestSuite.sol";
import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
/* solhint-disable state-visibility */

abstract contract SignatureCheckerTestSuite is IdRegistryTestSuite {
    function setUp() public override {
        super.setUp();
    }
}
