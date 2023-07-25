// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../TestConstants.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyRegistryTest is KeyRegistryTestSuite {
    function setUp() public override {
        super.setUp();

        vm.prank(owner);
        idRegistry.disableTrustedOnly();
    }

    event Add(uint256 indexed fid, uint32 indexed scheme, bytes indexed key, bytes keyBytes, bytes metadata);
    event Remove(uint256 indexed fid, bytes indexed key, bytes keyBytes);
    event AdminReset(uint256 indexed fid, bytes indexed key, bytes keyBytes);
    event Migrated(uint256 indexed keysMigratedAt);

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
        assertEq(keyRegistry.owner(), owner);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(keyRegistry.isMigrated(), false);
    }

    /*//////////////////////////////////////////////////////////////
                                   ADD
    //////////////////////////////////////////////////////////////*/

    function testFuzzAdd(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);

        vm.expectEmit();
        emit Add(fid, scheme, key, key, metadata);
        vm.prank(to);
        keyRegistry.add(scheme, key, metadata);

        assertAdded(fid, key, scheme);
    }

    function testFuzzAddRevertsUnlessFidOwner(
        address to,
        address recovery,
        address caller,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(caller);
        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.add(scheme, key, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsIfStateNotNull(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.add(scheme, key, metadata);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.add(scheme, key, metadata);

        vm.stopPrank();
        assertAdded(fid, key, scheme);
    }

    function testFuzzAddRevertsIfRemoved(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.add(scheme, key, metadata);
        keyRegistry.remove(key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.add(scheme, key, metadata);

        vm.stopPrank();
        assertRemoved(fid, key, scheme);
    }

    function testFuzzAddFor(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, scheme, key, metadata, deadline);

        vm.expectEmit();
        emit Add(fid, scheme, key, key, metadata);
        vm.prank(registrar);
        keyRegistry.addFor(owner, scheme, key, metadata, deadline, sig);

        assertAdded(fid, key, scheme);
    }

    function testFuzzAddForRevertsNoFid(
        address registrar,
        uint256 ownerPk,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        bytes memory sig = _signAdd(ownerPk, owner, scheme, key, metadata, deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.addFor(owner, scheme, key, metadata, deadline, sig);
    }

    function testFuzzAddForRevertsInvalidSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, scheme, key, metadata, deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(KeyRegistry.InvalidSignature.selector);
        keyRegistry.addFor(owner, scheme, key, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsBadSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(registrar);
        vm.expectRevert("ECDSA: invalid signature");
        keyRegistry.addFor(owner, scheme, key, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsExpiredSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, scheme, key, metadata, deadline);

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(KeyRegistry.SignatureExpired.selector);
        keyRegistry.addFor(owner, scheme, key, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzTrustedAdd(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.prank(owner);
        keyRegistry.setTrustedCaller(trustedCaller);

        uint256 fid = _registerFid(to, recovery);

        vm.expectEmit();
        emit Add(fid, scheme, key, key, metadata);
        vm.prank(trustedCaller);
        keyRegistry.trustedAdd(to, scheme, key, metadata);

        assertAdded(fid, key, scheme);
    }

    function testFuzzTrustedAddRevertsNotTrustedCaller(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.assume(to != trustedCaller);

        vm.prank(owner);
        keyRegistry.setTrustedCaller(trustedCaller);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(to);
        vm.expectRevert(TrustedCaller.OnlyTrustedCaller.selector);
        keyRegistry.trustedAdd(to, scheme, key, metadata);

        assertNull(fid, key);
    }

    function testFuzzTrustedAddRevertsUnownedFid(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.prank(owner);
        keyRegistry.setTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.trustedAdd(to, scheme, key, metadata);
    }

    function testFuzzTrustedAddRevertsTrustedOnly(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.startPrank(owner);
        keyRegistry.setTrustedCaller(trustedCaller);
        keyRegistry.disableTrustedOnly();
        vm.stopPrank();

        uint256 fid = _registerFid(to, recovery);

        vm.prank(trustedCaller);
        vm.expectRevert(TrustedCaller.Registrable.selector);
        keyRegistry.trustedAdd(to, scheme, key, metadata);

        assertNull(fid, key);
    }

    /*//////////////////////////////////////////////////////////////
                                 REMOVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRemove(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);

        vm.prank(to);
        keyRegistry.add(scheme, key, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        vm.expectEmit();
        emit Remove(fid, key, key);
        vm.prank(to);
        keyRegistry.remove(key);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        assertRemoved(fid, key, scheme);
    }

    function testFuzzRemoveRevertsUnlessFidOwner(
        address to,
        address recovery,
        address caller,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.prank(to);
        keyRegistry.add(scheme, key, metadata);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.remove(key);

        assertAdded(fid, key, scheme);
    }

    function testFuzzRemoveRevertsIfNull(address to, address recovery, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        vm.prank(to);
        keyRegistry.remove(key);

        assertNull(fid, key);
    }

    function testFuzzRemoveRevertsIfRemoved(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.add(scheme, key, metadata);
        keyRegistry.remove(key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.remove(key);

        vm.stopPrank();
        assertRemoved(fid, key, scheme);
    }

    function testFuzzRemoveFor(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(owner);
        keyRegistry.add(scheme, key, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        vm.expectEmit();
        emit Remove(fid, key, key);
        vm.prank(registrar);
        keyRegistry.removeFor(owner, key, deadline, sig);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        assertRemoved(fid, key, scheme);
    }

    function testFuzzRemoveForRevertsNoFid(
        address registrar,
        uint256 ownerPk,
        bytes calldata key,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(registrar);
        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);
    }

    function testFuzzRemoveForRevertsInvalidSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline + 1);

        vm.prank(owner);
        keyRegistry.add(scheme, key, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        vm.prank(registrar);
        vm.expectRevert(KeyRegistry.InvalidSignature.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, scheme);
    }

    function testFuzzRemoveForRevertsBadSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(owner);
        keyRegistry.add(scheme, key, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        vm.prank(registrar);
        vm.expectRevert("ECDSA: invalid signature");
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, scheme);
    }

    function testFuzzRemoveForRevertsExpiredSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(owner);
        keyRegistry.add(scheme, key, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(KeyRegistry.SignatureExpired.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, scheme);
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzMigration(uint40 timestamp) public {
        vm.assume(timestamp != 0);

        vm.warp(timestamp);
        vm.expectEmit();
        emit Migrated(timestamp);
        vm.prank(owner);
        keyRegistry.migrateKeys();

        assertEq(keyRegistry.isMigrated(), true);
        assertEq(keyRegistry.keysMigratedAt(), timestamp);
    }

    function testFuzzOnlyOwnerCanMigrate(address caller) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.migrateKeys();

        assertEq(keyRegistry.isMigrated(), false);
        assertEq(keyRegistry.keysMigratedAt(), 0);
    }

    function testFuzzCannotMigrateTwice(uint40 timestamp) public {
        timestamp = uint40(bound(timestamp, 1, type(uint40).max));
        vm.warp(timestamp);
        vm.prank(owner);
        keyRegistry.migrateKeys();

        timestamp = uint40(bound(timestamp, timestamp, type(uint40).max));
        vm.expectRevert(KeyRegistry.AlreadyMigrated.selector);
        vm.prank(owner);
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

        vm.prank(owner);
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
        emit Add(ids[0], 1, keys[0][0], keys[0][0], metadata);

        vm.expectEmit();
        emit Add(ids[1], 1, keys[1][0], keys[1][0], metadata);

        vm.expectEmit();
        emit Add(ids[2], 1, keys[2][0], keys[2][0], metadata);

        vm.expectEmit();
        emit Add(ids[2], 1, keys[2][1], keys[2][1], metadata);

        vm.prank(owner);
        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);
    }

    function testFuzzBulkAddKeyForMigrationDuringGracePeriod(uint40 _warpForward, bytes calldata metadata) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);
        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(owner);

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

        vm.startPrank(owner);

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

        vm.startPrank(owner);

        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.bulkAddKeysForMigration(ids, keys, metadata);

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigrationRevertsMismatchedInput() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](1);
        bytes memory metadata = new bytes(1);

        vm.startPrank(owner);
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

        vm.startPrank(owner);

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

        vm.startPrank(owner);

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
        vm.prank(owner);
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

        vm.startPrank(owner);

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

        vm.startPrank(owner);

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

        vm.startPrank(owner);

        keyRegistry.migrateKeys();
        vm.warp(keyRegistry.keysMigratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationRevertsMismatchedInput() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](1);

        vm.startPrank(owner);
        vm.expectRevert(KeyRegistry.InvalidBatchInput.selector);
        keyRegistry.bulkResetKeysForMigration(ids, keys);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        vm.prank(to);
        return idRegistry.register(recovery);
    }

    function assertEq(KeyRegistry.KeyState a, KeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint32 scheme) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);
    }

    function assertRemoved(uint256 fid, bytes memory key, uint32 scheme) internal {
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
