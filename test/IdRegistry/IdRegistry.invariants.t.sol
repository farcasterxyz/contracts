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

    function invariant_allRecoveryAddrsAssociatedWithFid() public {
        address[] memory recoveryAddrs = handler.recoveryAddrs();
        for (uint256 i; i < recoveryAddrs.length; ++i) {
            address recovery = recoveryAddrs[i];
            uint256[] memory fids = handler.fidsByRecoveryAddr(recovery);
            for (uint256 j; j < fids.length; ++j) {
                uint256 fid = fids[j];
                if (fid != 0) {
                    assertEq(idRegistry.getRecoveryOf(fid), recovery);
                }
            }
        }
    }
}
