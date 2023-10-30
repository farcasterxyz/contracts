// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {Migration} from "../../../src/lib/Migration.sol";

contract MigrationExample is Migration {
    constructor(uint256 gracePeriod, address migrator) Migration(uint24(gracePeriod), migrator) {}

    function onlyCallableDuringMigration() external migration {}
}

contract MigrationSymTest is SymTest, Test {
    MigrationExample migration;
    address migrator;
    uint256 gracePeriod;

    function setUp() public {
        migrator = address(0x1000);

        // Create symbolic gracePeriod
        gracePeriod = svm.createUint256("gracePeriod");

        // Setup Migration
        migration = new MigrationExample(gracePeriod, migrator);
    }

    function check_Invariants(bytes4 selector, address caller) public {
        _initState();

        // Record pre-state
        uint40 oldMigratedAt = migration.migratedAt();

        // Execute an arbitrary tx
        vm.prank(caller);
        (bool success,) = address(migration).call(_calldataFor(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        uint40 newMigratedAt = migration.migratedAt();

        bool isMigrated = migration.isMigrated();
        bool isInGracePeriod = block.timestamp <= migration.migratedAt() + migration.gracePeriod();

        // If the migratedAt timestamp is changed by any transaction...
        if (newMigratedAt != oldMigratedAt) {
            // The previous value was zero.
            assert(oldMigratedAt == 0);

            // The function called was migrate().
            assert(selector == migration.migrate.selector);

            // The caller must be the migrator.
            assert(caller == migrator);
        }

        // If the call was protected by a migration modifier...
        if (selector == migration.onlyCallableDuringMigration.selector) {
            // The state must be unchanged.
            assert(newMigratedAt == oldMigratedAt);

            // The caller must be the migrator.
            assert(caller == migrator);

            // The contract is unmigrated or in the grace period.
            assert(!isMigrated || isInGracePeriod);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initialize IdRegistry with symbolic arguments for state.
     */
    function _initState() public {
        if (svm.createBool("isMigrated?")) {
            vm.prank(migrator);
            migration.migrate();
        }
    }

    /**
     * @dev Generates valid calldata for a given function selector.
     */
    function _calldataFor(bytes4 selector) internal returns (bytes memory) {
        return abi.encodePacked(selector, svm.createBytes(1024, "data"));
    }
}
