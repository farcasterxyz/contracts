// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {Migration} from "../../../src/abstract/Migration.sol";

contract MigrationExample is Migration {
    constructor(uint256 gracePeriod, address migrator, address owner) Migration(uint24(gracePeriod), migrator, owner) {}

    function onlyCallableDuringMigration() external onlyMigrator {}
}

contract MigrationSymTest is SymTest, Test {
    MigrationExample migration;
    address migrator;
    address owner;
    uint256 gracePeriod;

    function setUp() public {
        owner = address(0x1000);
        migrator = address(0x2000);

        // Create symbolic gracePeriod
        gracePeriod = svm.createUint256("gracePeriod");

        // Setup Migration
        migration = new MigrationExample(gracePeriod, migrator, owner);
    }

    function check_Invariants(bytes4 selector, address caller) public {
        _initState();

        // Record pre-state
        uint40 oldMigratedAt = migration.migratedAt();
        address oldMigrator = migration.migrator();

        // Execute an arbitrary tx
        vm.prank(caller);
        (bool success,) = address(migration).call(_calldataFor(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        uint40 newMigratedAt = migration.migratedAt();
        address newMigrator = migration.migrator();

        bool isPaused = migration.paused();
        bool isMigrated = migration.isMigrated();
        bool isInGracePeriod = block.timestamp <= migration.migratedAt() + migration.gracePeriod();

        // If the migratedAt timestamp is changed by any transaction...
        if (newMigratedAt != oldMigratedAt) {
            // The previous value was zero.
            assert(oldMigratedAt == 0);

            // The function called was migrate().
            assert(selector == migration.migrate.selector);

            // The caller must be the migrator.
            assert(caller == oldMigrator && oldMigrator == newMigrator);

            // The contract is paused.
            assert(isPaused);
        }

        // If the migrator address is changed by any transaction...
        if (newMigrator != oldMigrator) {
            // The function called was setMigrator().
            assert(selector == migration.setMigrator.selector);

            // The caller must be the owner.
            assert(caller == owner);

            // The contract is unmigrated.
            assert(oldMigratedAt == 0 && oldMigratedAt == newMigratedAt);

            // The contract is paused.
            assert(isPaused);
        }

        // If the call was protected by a migration modifier...
        if (selector == migration.onlyCallableDuringMigration.selector) {
            // The state must be unchanged.
            assert(newMigratedAt == oldMigratedAt);

            // The caller must be the migrator.
            assert(caller == oldMigrator && oldMigrator == newMigrator);

            // The contract is unmigrated or in the grace period.
            assert(!isMigrated || isInGracePeriod);

            // The contract is paused.
            assert(isPaused);
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
            vm.prank(migration.migrator());
            migration.migrate();
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
