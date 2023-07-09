// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../TestConstants.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyRegistryTest is KeyRegistryTestSuite {
    event Add(uint256 indexed fid, bytes indexed key, bytes keyBytes, uint200 indexed scheme, bytes metadata);
    event Remove(uint256 indexed fid, bytes indexed key, bytes keyBytes);
    event AdminReset(uint256 indexed fid, bytes indexed key, bytes keyBytes);
    event Migrated();

    function testInitialIdRegistry() public {
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
    }

    function testInitialGracePeriod() public {
        assertEq(keyRegistry.gracePeriod(), 1 days);
    }

    function testInitialMigrationTimestamp() public {
        assertEq(keyRegistry.keysMigratedAt(), 0);
    }

    function testInitialOwner() public {
        assertEq(keyRegistry.owner(), admin);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(keyRegistry.isMigrated(), false);
    }

    /*//////////////////////////////////////////////////////////////
                                   ADD
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(
        address to,
        address recovery,
        uint200 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);

        vm.expectEmit();
        emit Add(fid, key, key, scheme, metadata);
        vm.prank(to);
        keyRegistry.add(fid, scheme, key, metadata);

        assertAdded(fid, key, scheme);
    }

    function testFuzzRegisterRevertsUnlessFidOwner(
        address to,
        address recovery,
        address caller,
        uint200 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(caller);
        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.add(fid, scheme, key, metadata);

        assertNull(fid, key);
    }

    function testFuzzRegisterRevertsIfStateNotNull(
        address to,
        address recovery,
        uint200 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.add(fid, scheme, key, metadata);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.add(fid, scheme, key, metadata);

        vm.stopPrank();
        assertAdded(fid, key, scheme);
    }

    function testFuzzAddRevertsIfRemoved(
        address to,
        address recovery,
        uint200 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.add(fid, scheme, key, metadata);
        keyRegistry.remove(fid, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.add(fid, scheme, key, metadata);

        vm.stopPrank();
        assertRemoved(fid, key, scheme);
    }

    /*//////////////////////////////////////////////////////////////
                                 REMOVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRemove(
        address to,
        address recovery,
        uint200 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);

        vm.prank(to);
        keyRegistry.add(fid, scheme, key, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        vm.expectEmit();
        emit Remove(fid, key, key);
        vm.prank(to);
        keyRegistry.remove(fid, key);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        assertRemoved(fid, key, scheme);
    }

    function testFuzzRemoveRevertsUnlessFidOwner(
        address to,
        address recovery,
        address caller,
        uint200 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.prank(to);
        keyRegistry.add(fid, scheme, key, metadata);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.remove(fid, key);

        assertAdded(fid, key, scheme);
    }

    function testFuzzRemoveRevertsIfNull(address to, address recovery, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        vm.prank(to);
        keyRegistry.remove(fid, key);

        assertNull(fid, key);
    }

    function testFuzzRemoveRevertsIfRemoved(
        address to,
        address recovery,
        uint200 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.add(fid, scheme, key, metadata);
        keyRegistry.remove(fid, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.remove(fid, key);

        vm.stopPrank();
        assertRemoved(fid, key, scheme);
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzMigration(uint40 timestamp) public {
        vm.assume(timestamp != 0);

        vm.warp(timestamp);
        vm.expectEmit();
        emit Migrated();
        vm.prank(admin);
        keyRegistry.migrateKeys();

        assertEq(keyRegistry.isMigrated(), true);
        assertEq(keyRegistry.keysMigratedAt(), timestamp);
    }

    function testFuzzOnlyOwnerCanMigrate(address caller) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.migrateKeys();

        assertEq(keyRegistry.isMigrated(), false);
        assertEq(keyRegistry.keysMigratedAt(), 0);
    }

    function testFuzzCannotMigrateTwice(uint40 timestamp) public {
        timestamp = uint40(bound(timestamp, 1, type(uint40).max));
        vm.warp(timestamp);
        vm.prank(admin);
        keyRegistry.migrateKeys();

        timestamp = uint40(bound(timestamp, timestamp, type(uint40).max));
        vm.expectRevert(KeyRegistry.AlreadyMigrated.selector);
        vm.prank(admin);
        keyRegistry.migrateKeys();

        assertEq(keyRegistry.isMigrated(), true);
        assertEq(keyRegistry.keysMigratedAt(), timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                BULK ADD
    //////////////////////////////////////////////////////////////*/

    function testFuzzBulkAddSignerForMigration(uint256[] memory _ids, uint8 _numKeys, bytes calldata metadata) public {
        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);
        uint256 numKeys = bound(_numKeys, 1, 10);

        uint256[] memory ids = _dedupeFuzzedIds(_ids, len);
        uint256 idsLength = ids.length;
        bytes[][] memory keys = _constructKeys(idsLength, numKeys);

        vm.prank(admin);
        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertAdded(ids[i], keys[i][j], 1);
            }
        }
    }

    function testBulkAddEmitsEvent() public {
        uint256[] memory ids = new uint256[](3);
        bytes[][] memory keys = new bytes[][](3);
        bytes memory metadata = new bytes(1);

        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        keys[0] = new bytes[](1);
        keys[1] = new bytes[](1);
        keys[2] = new bytes[](2);

        keys[0][0] = abi.encodePacked(uint256(1));
        keys[1][0] = abi.encodePacked(uint256(2));
        keys[2][0] = abi.encodePacked(uint256(3));
        keys[2][1] = abi.encodePacked(uint256(4));

        vm.expectEmit();
        emit Add(ids[0], keys[0][0], keys[0][0], 1, metadata);

        vm.expectEmit();
        emit Add(ids[1], keys[1][0], keys[1][0], 1, metadata);

        vm.expectEmit();
        emit Add(ids[2], keys[2][0], keys[2][0], 1, metadata);

        vm.expectEmit();
        emit Add(ids[2], keys[2][1], keys[2][1], 1, metadata);

        vm.prank(admin);
        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);
    }

    function testFuzzBulkAddKeyForMigrationDuringGracePeriod(uint40 _warpForward, bytes calldata metadata) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);
        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(admin);

        keyRegistry.migrateKeys();
        vm.warp(keyRegistry.keysMigratedAt() + warpForward);

        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigrationAfterGracePeriodRevertsUnauthorized(
        uint40 _warpForward,
        bytes calldata metadata
    ) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);
        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.keysMigratedAt());

        vm.startPrank(admin);

        keyRegistry.migrateKeys();
        vm.warp(keyRegistry.keysMigratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.stopPrank();
    }

    function testBulkAddCannotReadd() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](2);
        bytes memory metadata = new bytes(1);

        ids[0] = 1;
        ids[1] = 2;

        keys[0] = new bytes[](1);
        keys[1] = new bytes[](1);

        keys[0][0] = abi.encodePacked(uint256(1));
        keys[1][0] = abi.encodePacked(uint256(2));

        vm.startPrank(admin);

        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigrationRevertsMismatchedInput() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](1);
        bytes memory metadata = new bytes(1);

        vm.startPrank(admin);
        vm.expectRevert(KeyRegistry.InvalidBatchInput.selector);
        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               BULK REMOVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzBulkRemoveSignerForMigration(
        uint256[] memory _ids,
        uint8 _numKeys,
        bytes calldata metadata
    ) public {
        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);
        uint256 numKeys = bound(_numKeys, 1, 10);

        uint256[] memory ids = _dedupeFuzzedIds(_ids, len);
        uint256 idsLength = ids.length;
        bytes[][] memory keys = _constructKeys(idsLength, numKeys);

        vm.startPrank(admin);

        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);
        keyRegistry.bulkResetKeysForMigration(ids, keys);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertNull(ids[i], keys[i][j]);
            }
        }

        vm.stopPrank();
    }

    function testBulkResetEmitsEvent() public {
        uint256[] memory ids = new uint256[](3);
        bytes[][] memory keys = new bytes[][](3);
        bytes memory metadata = new bytes(1);

        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        keys[0] = new bytes[](1);
        keys[1] = new bytes[](1);
        keys[2] = new bytes[](2);

        // TODO: make a reusable helper to handle key and id generation

        keys[0][0] = abi.encodePacked(uint256(1));
        keys[1][0] = abi.encodePacked(uint256(2));
        keys[2][0] = abi.encodePacked(uint256(3));
        keys[2][1] = abi.encodePacked(uint256(4));

        vm.startPrank(admin);

        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.expectEmit();
        emit AdminReset(ids[0], keys[0][0], keys[0][0]);

        vm.expectEmit();
        emit AdminReset(ids[1], keys[1][0], keys[1][0]);

        vm.expectEmit();
        emit AdminReset(ids[2], keys[2][0], keys[2][0]);

        vm.expectEmit();
        emit AdminReset(ids[2], keys[2][1], keys[2][1]);

        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.stopPrank();
    }

    function testBulkResetRevertsWithoutAdding() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](2);

        ids[0] = 1;
        ids[1] = 2;

        keys[0] = new bytes[](1);
        keys[1] = new bytes[](1);

        keys[0][0] = abi.encodePacked(uint256(1));
        keys[1][0] = abi.encodePacked(uint256(2));

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        vm.prank(admin);
        keyRegistry.bulkResetKeysForMigration(ids, keys);
    }

    function testBulkResetRevertsIfRunTwice() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](2);
        bytes memory metadata = new bytes(1);

        ids[0] = 1;
        ids[1] = 2;

        keys[0] = new bytes[](1);
        keys[1] = new bytes[](1);

        keys[0][0] = abi.encodePacked(uint256(1));
        keys[1][0] = abi.encodePacked(uint256(2));

        vm.startPrank(admin);

        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);
        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationDuringGracePeriod(uint40 _warpForward) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);
        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(admin);

        keyRegistry.migrateKeys();
        vm.warp(keyRegistry.keysMigratedAt() + warpForward);

        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationAfterGracePeriodRevertsUnauthorized(uint40 _warpForward) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.keysMigratedAt());

        vm.startPrank(admin);

        keyRegistry.migrateKeys();
        vm.warp(keyRegistry.keysMigratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationRevertsMismatchedInput() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](1);

        vm.startPrank(admin);
        vm.expectRevert(KeyRegistry.InvalidBatchInput.selector);
        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        return idRegistry.register(to, recovery);
    }

    function assertEq(KeyRegistry.KeyState a, KeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint200 scheme) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);
    }

    function assertRemoved(uint256 fid, bytes memory key, uint200 scheme) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);
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
