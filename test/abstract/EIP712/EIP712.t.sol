// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {EIP712} from "../../../src/abstract/EIP712.sol";
import {TestSuiteSetup} from "../../TestSuiteSetup.sol";

/* solhint-disable state-visibility */
/* solhint-disable no-empty-blocks */

contract EIP712Example is EIP712("EIP712 Example", "1") {}

contract EIP712Test is TestSuiteSetup {
    EIP712Example eip712;

    function setUp() public override {
        super.setUp();

        eip712 = new EIP712Example();
    }

    function testExposesDomainSeparator() public {
        assertEq(eip712.domainSeparatorV4(), 0x0617e266f62048821cb1d443cca5b7a0e073cb89f23c9f20046cdf79ecb42429);
    }
}
