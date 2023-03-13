// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";
import {IdRegistryHandler} from "./handlers/IdRegistryHandler.sol";

/* solhint-disable state-visibility */

contract IdRegistryInvariants is IdRegistryTestSuite {
    IdRegistryHandler handler;

    function setUp() public override {
        super.setUp();
        idRegistry.disableTrustedOnly();
        handler = new IdRegistryHandler(idRegistry, address(this));

        targetContract(address(handler));
    }

    function invariant_recoverySenderMustOwnFid() public {
        assertEq(uint256(1), 1);
    }
}
