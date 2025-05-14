// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {KeyRegistry, IKeyRegistry} from "../../src/KeyRegistry.sol";
import {IMigration} from "../../src/abstract/Migration.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";

import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";
import {BulkAddDataBuilder, BulkResetDataBuilder} from "./KeyRegistryTestHelpers.sol";

/* solhint-disable state-visibility */

contract KeyRegistryTest is KeyRegistryTestSuite {
    using BulkAddDataBuilder for KeyRegistry.BulkAddData[];
    using BulkResetDataBuilder for KeyRegistry.BulkResetData[];

    function setUp() public override {
        super.setUp();

        // Pause the KeyRegistry. Migrations must take place when paused.
        vm.prank(owner);
        keyRegistry.pause();
    }

    event Add(
        uint256 indexed fid,
        uint32 indexed keyType,
        bytes indexed key,
        bytes keyBytes,
        uint8 metadataType,
        bytes metadata
    );
    event Remove(uint256 indexed fid, bytes indexed key, bytes keyBytes);
    event AdminReset(uint256 indexed fid, bytes indexed key, bytes keyBytes);
    event Migrated(uint256 indexed migratedAt);
    event SetMigrator(address oldMigrator, address newMigrator);

    function testInitialGracePeriod() public {
        assertEq(keyRegistry.gracePeriod(), 1 days);
    }

    function testInitialMigrationTimestamp() public {
        assertEq(keyRegistry.migratedAt(), 0);
    }

    function testInitialMigrator() public {
        assertEq(keyRegistry.migrator(), migrator);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(keyRegistry.isMigrated(), false);
    }

    /*//////////////////////////////////////////////////////////////
                             SET MIGRATOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzOwnerCanSetMigrator(
        address migrator
    ) public {
        address oldMigrator = keyRegistry.migrator();

        vm.expectEmit();
        emit SetMigrator(oldMigrator, migrator);
        vm.prank(owner);
        keyRegistry.setMigrator(migrator);

        assertEq(keyRegistry.migrator(), migrator);
    }

    function testFuzzSetMigratorRevertsWhenMigrated(
        address migrator
    ) public {
        address oldMigrator = keyRegistry.migrator();

        vm.prank(oldMigrator);
        keyRegistry.migrate();

        vm.prank(owner);
        vm.expectRevert(IMigration.AlreadyMigrated.selector);
        keyRegistry.setMigrator(migrator);

        assertEq(keyRegistry.migrator(), oldMigrator);
    }

    function testFuzzSetMigratorRevertsWhenUnpaused(
        address migrator
    ) public {
        address oldMigrator = keyRegistry.migrator();

        vm.startPrank(owner);
        keyRegistry.unpause();
        vm.expectRevert("Pausable: not paused");
        keyRegistry.setMigrator(migrator);
        vm.stopPrank();

        assertEq(keyRegistry.migrator(), oldMigrator);
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzMigration(
        uint40 timestamp
    ) public {
        vm.assume(timestamp != 0);

        vm.warp(timestamp);
        vm.expectEmit();
        emit Migrated(timestamp);
        vm.prank(migrator);
        keyRegistry.migrate();

        assertEq(keyRegistry.isMigrated(), true);
        assertEq(keyRegistry.migratedAt(), timestamp);
    }

    function testFuzzOnlyMigratorCanMigrate(
        address caller
    ) public {
        vm.assume(caller != migrator);

        vm.prank(caller);
        vm.expectRevert(IMigration.OnlyMigrator.selector);
        keyRegistry.migrate();

        assertEq(keyRegistry.isMigrated(), false);
        assertEq(keyRegistry.migratedAt(), 0);
    }

    function testFuzzCannotMigrateTwice(
        uint40 timestamp
    ) public {
        timestamp = uint40(bound(timestamp, 1, type(uint40).max));
        vm.warp(timestamp);
        vm.prank(migrator);
        keyRegistry.migrate();

        timestamp = uint40(bound(timestamp, timestamp, type(uint40).max));
        vm.expectRevert(IMigration.AlreadyMigrated.selector);
        vm.prank(migrator);
        keyRegistry.migrate();

        assertEq(keyRegistry.isMigrated(), true);
        assertEq(keyRegistry.migratedAt(), timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                BULK ADD
    //////////////////////////////////////////////////////////////*/

    function testFuzzBulkAddSignerForMigration(uint256[] memory _ids, uint8 _numKeys) public {
        _registerValidator(1, 1, false);

        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);
        uint256 numKeys = bound(_numKeys, 1, 10);

        uint256[] memory ids = _dedupeFuzzedIds(_ids, len);
        uint256 idsLength = ids.length;
        bytes[][] memory keys = _constructKeys(idsLength, numKeys);
        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFidsWithKeys(ids, keys);

        vm.prank(migrator);
        keyRegistry.bulkAddKeysForMigration(addItems);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertAdded(ids[i], keys[i][j], 1);
            }
            assertEq(keyRegistry.totalKeys(ids[i], IKeyRegistry.KeyState.ADDED), keys[i].length);
            assertEq(keyRegistry.totalKeys(ids[i], IKeyRegistry.KeyState.REMOVED), 0);
        }
    }

    function testBulkAddEmitsEvent() public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1")
            .addFid(2).addKey(1, "key2", "metadata2").addFid(3).addKey(2, "key3", "metadata3").addKey(
            2, "key4", "metadata4"
        );

        vm.expectEmit();
        emit Add(1, 1, "key1", "key1", 1, "metadata1");

        vm.expectEmit();
        emit Add(2, 1, "key2", "key2", 1, "metadata2");

        vm.expectEmit();
        emit Add(3, 1, "key3", "key3", 1, "metadata3");

        vm.expectEmit();
        emit Add(3, 1, "key4", "key4", 1, "metadata4");

        vm.prank(migrator);
        keyRegistry.bulkAddKeysForMigration(addItems);
    }

    function testFuzzBulkAddKeyForMigrationDuringGracePeriod(
        uint40 _warpForward
    ) public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1");

        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(migrator);

        keyRegistry.migrate();
        vm.warp(keyRegistry.migratedAt() + warpForward);

        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigrationAfterGracePeriodRevertsUnauthorized(
        uint40 _warpForward
    ) public {
        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1");

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.migratedAt());

        vm.startPrank(migrator);

        keyRegistry.migrate();
        vm.warp(keyRegistry.migratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(IMigration.PermissionRevoked.selector);
        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.stopPrank();
    }

    function testBulkAddCannotReAdd() public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems =
            BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1").addFid(2).addKey(1, "key2", "metadata2");

        vm.startPrank(migrator);

        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.stopPrank();
    }

    function testBulkAddRevertsWhenUnpaused() public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems =
            BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1").addFid(2).addKey(1, "key2", "metadata2");

        vm.prank(owner);
        keyRegistry.unpause();

        vm.prank(migrator);
        vm.expectRevert("Pausable: not paused");
        keyRegistry.bulkAddKeysForMigration(addItems);
    }

    /*//////////////////////////////////////////////////////////////
                               BULK REMOVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzBulkRemoveSignerForMigration(uint256[] memory _ids, uint8 _numKeys) public {
        _registerValidator(1, 1);

        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);
        uint256 numKeys = bound(_numKeys, 1, 10);

        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty();
        KeyRegistry.BulkResetData[] memory resetItems = BulkResetDataBuilder.empty();

        uint256[] memory ids = _dedupeFuzzedIds(_ids, len);
        uint256 idsLength = ids.length;
        for (uint256 i; i < idsLength; ++i) {
            addItems = addItems.addFid(ids[i]);
            resetItems = resetItems.addFid(ids[i]);
        }
        bytes[][] memory keys = _constructKeys(idsLength, numKeys);
        for (uint256 i; i < keys.length; ++i) {
            bytes[] memory fidKeys = keys[i];
            for (uint256 j; j < fidKeys.length; ++j) {
                addItems = addItems.addKey(i, fidKeys[j], bytes.concat("metadata-", fidKeys[j]));
                resetItems = resetItems.addKey(i, fidKeys[j]);
            }
        }

        vm.startPrank(migrator);

        keyRegistry.bulkAddKeysForMigration(addItems);

        for (uint256 i; i < idsLength; ++i) {
            assertEq(keyRegistry.totalKeys(ids[i], IKeyRegistry.KeyState.ADDED), keys[i].length);
            assertEq(keyRegistry.totalKeys(ids[i], IKeyRegistry.KeyState.REMOVED), 0);
        }

        keyRegistry.bulkResetKeysForMigration(resetItems);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertNull(ids[i], keys[i][j]);
            }
            assertEq(keyRegistry.totalKeys(ids[i], IKeyRegistry.KeyState.ADDED), 0);
            assertEq(keyRegistry.totalKeys(ids[i], IKeyRegistry.KeyState.REMOVED), 0);
        }

        vm.stopPrank();
    }

    function testBulkResetEmitsEvent() public {
        _registerValidator(1, 1);
        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1")
            .addFid(2).addKey(1, "key2", "metadata2").addFid(3).addKey(2, "key3", "metadata3").addKey(
            2, "key4", "metadata4"
        );

        KeyRegistry.BulkResetData[] memory resetItems = BulkResetDataBuilder.empty().addFid(1).addKey(0, "key1").addFid(
            2
        ).addKey(1, "key2").addFid(3).addKey(2, "key3").addKey(2, "key4");

        vm.startPrank(migrator);

        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.expectEmit();
        emit AdminReset(1, "key1", "key1");

        vm.expectEmit();
        emit AdminReset(2, "key2", "key2");

        vm.expectEmit();
        emit AdminReset(3, "key3", "key3");

        vm.expectEmit();
        emit AdminReset(3, "key4", "key4");

        keyRegistry.bulkResetKeysForMigration(resetItems);

        vm.stopPrank();
    }

    function testBulkResetRevertsWithoutAdding() public {
        _registerValidator(1, 1);

        KeyRegistry.BulkResetData[] memory resetItems =
            BulkResetDataBuilder.empty().addFid(1).addKey(0, "key1").addFid(2).addKey(1, "key2");

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        vm.prank(migrator);
        keyRegistry.bulkResetKeysForMigration(resetItems);
    }

    function testBulkResetRevertsIfRunTwice() public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems =
            BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1").addFid(2).addKey(1, "key2", "metadata2");

        KeyRegistry.BulkResetData[] memory resetItems =
            BulkResetDataBuilder.empty().addFid(1).addKey(0, "key1").addFid(2).addKey(1, "key2");

        vm.startPrank(migrator);

        keyRegistry.bulkAddKeysForMigration(addItems);
        keyRegistry.bulkResetKeysForMigration(resetItems);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.bulkResetKeysForMigration(resetItems);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationDuringGracePeriod(
        uint40 _warpForward
    ) public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key", "metadata");

        KeyRegistry.BulkResetData[] memory resetItems = BulkResetDataBuilder.empty().addFid(1).addKey(0, "key");

        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(migrator);

        keyRegistry.bulkAddKeysForMigration(addItems);
        keyRegistry.migrate();
        vm.warp(keyRegistry.migratedAt() + warpForward);

        keyRegistry.bulkResetKeysForMigration(resetItems);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationAfterGracePeriodRevertsUnauthorized(
        uint40 _warpForward
    ) public {
        KeyRegistry.BulkResetData[] memory items = BulkResetDataBuilder.empty().addFid(1).addKey(0, "key");

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.migratedAt());

        vm.startPrank(migrator);

        keyRegistry.migrate();
        vm.warp(keyRegistry.migratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(IMigration.PermissionRevoked.selector);
        keyRegistry.bulkResetKeysForMigration(items);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationRevertsWhenUnpaused() public {
        KeyRegistry.BulkResetData[] memory items = BulkResetDataBuilder.empty().addFid(1).addKey(0, "key");

        vm.prank(owner);
        keyRegistry.unpause();

        vm.prank(migrator);
        vm.expectRevert("Pausable: not paused");
        keyRegistry.bulkResetKeysForMigration(items);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        vm.prank(idRegistry.idGateway());
        return idRegistry.register(to, recovery);
    }

    function assertEq(IKeyRegistry.KeyState a, IKeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }

    function assertRemoved(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }

    function _dedupeFuzzedIds(uint256[] memory _ids, uint256 len) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](len);
        uint256 idsLength;

        for (uint256 i; i < len; ++i) {
            bool found;
            for (uint256 j; j < idsLength; ++j) {
                if (ids[j] == _ids[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                ids[idsLength++] = _ids[i];
            }
        }

        assembly {
            mstore(ids, idsLength)
        }
    }

    function _constructKeys(uint256 idsLength, uint256 numKeys) internal pure returns (bytes[][] memory keys) {
        keys = new bytes[][](idsLength);
        for (uint256 i; i < idsLength; ++i) {
            keys[i] = new bytes[](numKeys);
            for (uint256 j; j < numKeys; ++j) {
                keys[i][j] = abi.encodePacked(j);
            }
        }
    }
}
