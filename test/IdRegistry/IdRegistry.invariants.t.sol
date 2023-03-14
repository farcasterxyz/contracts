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

    function invariant_allFidOwnersHaveRecoveryAddr() public {
        // Note to self: this is not the right property! recovery addrs are cleared on transfer...
        address[] memory fidOwners = handler.fidOwners();
        for (uint256 i; i < fidOwners.length; ++i) {
            address fidOwner = fidOwners[i];
            uint256 fid = idRegistry.idOf(fidOwner);
            address recovery = idRegistry.getRecoveryOf(fid);

            // fid exists
            assertTrue(fid != 0, "Zero fid");
            // recovery address exists
            assertTrue(recovery != address(0), "Zero recovery address");
        }
    }
}
