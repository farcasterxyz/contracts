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

    /// @notice All recovery addresses must be associated with a fid.
    function invariant_1_allRecoveryAddrsAssociatedWithFid() public {
        address[] memory recoveryAddrs = handler.recoveryAddrs();
        for (uint256 i; i < recoveryAddrs.length; ++i) {
            address recovery = recoveryAddrs[i];
            uint256[] memory fids = handler.fidsByRecoveryAddr(recovery);
            for (uint256 j; j < fids.length; ++j) {
                uint256 fid = fids[j];
                if (fid != 0) {
                    assertEq(idRegistry.getRecoveryOf(fid), recovery, "invariant 1");
                }
            }
        }
    }

    /// @notice If an address has a nonzero recovery state, it must own a fid.
    function invariant_2_nonzeroRecoveryStateMustOwnFid() public {
        uint256 latestFid = idRegistry.getIdCounter();
        for (uint256 fid; fid < latestFid; ++fid) {
            uint256 recoveryTs = idRegistry.getRecoveryTsOf(fid);
            if (recoveryTs != 0) {
                address recoveryAddr = idRegistry.getRecoveryOf(fid);
                address owner = handler.ownerOf(fid);
                uint256 ownerFid = idRegistry.idOf(owner);
                assertTrue(recoveryAddr != address(0), "invariant 2");
                assertEq(ownerFid, fid, "invariant 2");
            }
        }
    }

    /// @notice If an address has a nonzero recovery startTs, it must also have a destination.
    function invariant_3_nonzeroRecoveryStateMustHaveDestinationAddr() public {
        uint256 latestFid = idRegistry.getIdCounter();
        for (uint256 fid; fid < latestFid; ++fid) {
            uint256 recoveryTs = idRegistry.getRecoveryTsOf(fid);
            if (recoveryTs != 0) {
                assertTrue(idRegistry.getRecoveryDestinationOf(fid) != address(0), "invariant 3");
            }
        }
    }

    mapping(uint256 => bool) seenFids;

    /// @notice A nonzero address may only own one fid at a time. All fids must have a unique owner.
    function invariant_4_allFidsHaveUniqueOwner() public {
        address[] memory fidOwners = handler.fidOwners();
        for (uint256 i; i < fidOwners.length; ++i) {
            address owner = fidOwners[i];
            uint256 fid = idRegistry.idOf(owner);
            if (seenFids[fid]) {
                revert("invariant 4");
            }
            seenFids[fid] = true;
        }
    }
}
