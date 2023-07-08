// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../TestConstants.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyRegistryTest is KeyRegistryTestSuite {
    event Register(uint256 indexed fid, uint256 indexed keyType, bytes indexed key, bytes keyBytes);
    event Revoke(uint256 indexed fid, uint256 indexed keyType, bytes indexed key, bytes keyBytes);
    event Remove(uint256 indexed fid, uint256 indexed keyType, bytes indexed key, bytes keyBytes);
    event Freeze(uint256 indexed fid, uint256 indexed keyType, bytes indexed key, bytes keyBytes, bytes32 merkleRoot);

    function testInitialIdRegistry() public {
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
    }

    function testInitialGracePeriod() public {
        assertEq(keyRegistry.gracePeriod(), 1 days);
    }

    function testInitialMigrationTimestamp() public {
        assertEq(keyRegistry.signersMigratedAt(), 0);
    }

    function testInitialOwner() public {
        assertEq(keyRegistry.owner(), admin);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(keyRegistry.isMigrated(), false);
    }

    function testFuzzAddRevokeSigner(address to, address recovery, uint256 keyType, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);
        assertEq(keyRegistry.signerOf(fid, keyType, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.revoke(fid, keyType, key);
        assertEq(keyRegistry.signerOf(fid, keyType, key).state, KeyRegistry.SignerState.REVOKED);

        vm.stopPrank();
    }

    function testFuzzAddEmitsEvent(address to, address recovery, uint256 keyType, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        vm.expectEmit();
        emit Register(fid, keyType, key, key);
        keyRegistry.register(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzRevokeEmitsEvent(address to, address recovery, uint256 keyType, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);

        vm.expectEmit();
        emit Revoke(fid, keyType, key, key);
        keyRegistry.revoke(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzFreezeEmitsEvent(
        address to,
        address recovery,
        uint256 keyType,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(merkleRoot != bytes32(0));

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);

        vm.expectEmit();
        emit Freeze(fid, keyType, key, key, merkleRoot);
        keyRegistry.freeze(fid, keyType, key, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzAddRevertsNonOwner(
        address to,
        address recovery,
        address caller,
        uint256 keyType,
        bytes calldata key
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(caller);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.register(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzAddRevertsAuthorized(address to, address recovery, uint256 keyType, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.register(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzAddRevertsFrozen(
        address to,
        address recovery,
        uint256 keyType,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(merkleRoot != bytes32(0));

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);
        keyRegistry.freeze(fid, keyType, key, merkleRoot);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.register(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzAddRevertsRevoked(address to, address recovery, uint256 keyType, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);
        keyRegistry.revoke(fid, keyType, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.register(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzRevokeRevertsNonOwner(
        address to,
        address recovery,
        address caller,
        uint256 keyType,
        bytes calldata key
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.prank(to);
        keyRegistry.register(fid, keyType, key);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.revoke(fid, keyType, key);
    }

    function testFuzzRevokeRevertsUninitialized(
        address to,
        address recovery,
        uint256 keyType,
        bytes calldata key
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.revoke(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzRevokeRevertsRevoked(address to, address recovery, uint256 keyType, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);
        keyRegistry.revoke(fid, keyType, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.revoke(fid, keyType, key);

        vm.stopPrank();
    }

    function testFuzzAddFreezeSigner(
        address to,
        address recovery,
        uint256 keyType,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(merkleRoot != bytes32(0));

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);
        assertEq(keyRegistry.signerOf(fid, keyType, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.freeze(fid, keyType, key, merkleRoot);
        KeyRegistry.Signer memory signer = keyRegistry.signerOf(fid, keyType, key);
        assertEq(signer.state, KeyRegistry.SignerState.FROZEN);
        assertEq(signer.merkleRoot, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzFreezeRevertsEmptyRoot(address to, address recovery, uint256 keyType, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);

        vm.expectRevert(KeyRegistry.InvalidMerkleRoot.selector);
        keyRegistry.freeze(fid, keyType, key, bytes32(0));

        vm.stopPrank();
    }

    function testFuzzFreezeRevertsNonOwner(
        address to,
        address recovery,
        address caller,
        uint256 keyType,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(merkleRoot != bytes32(0));
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.prank(to);
        keyRegistry.register(fid, keyType, key);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.freeze(fid, keyType, key, merkleRoot);
    }

    function testFuzzFreezeRevertsUninitialized(
        address to,
        address recovery,
        uint256 keyType,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(merkleRoot != bytes32(0));

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.freeze(fid, keyType, key, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzFreezeRevertsFrozen(
        address to,
        address recovery,
        uint256 keyType,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(merkleRoot != bytes32(0));

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);
        assertEq(keyRegistry.signerOf(fid, keyType, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.freeze(fid, keyType, key, merkleRoot);
        KeyRegistry.Signer memory signer = keyRegistry.signerOf(fid, keyType, key);
        assertEq(signer.state, KeyRegistry.SignerState.FROZEN);
        assertEq(signer.merkleRoot, merkleRoot);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.freeze(fid, keyType, key, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzFreezeRevertsRevoked(
        address to,
        address recovery,
        uint256 keyType,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(merkleRoot != bytes32(0));

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, keyType, key);
        assertEq(keyRegistry.signerOf(fid, keyType, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.revoke(fid, keyType, key);
        assertEq(keyRegistry.signerOf(fid, keyType, key).state, KeyRegistry.SignerState.REVOKED);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.freeze(fid, keyType, key, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzMigration(uint40 timestamp) public {
        vm.assume(timestamp != 0);

        vm.warp(timestamp);
        vm.prank(admin);
        keyRegistry.migrateSigners();

        assertEq(keyRegistry.isMigrated(), true);
        assertEq(keyRegistry.signersMigratedAt(), timestamp);
    }

    function testFuzzOnlyOwnerCanMigrate(address caller) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.migrateSigners();
    }

    function testFuzzCannotMigrateTwice() public {
        vm.startPrank(admin);

        keyRegistry.migrateSigners();

        vm.expectRevert(KeyRegistry.AlreadyMigrated.selector);
        keyRegistry.migrateSigners();

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigration(uint256[] memory _ids, uint8 _numKeys) public {
        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);
        uint256 numKeys = bound(_numKeys, 1, 10);

        // bound and deduplicate fuzzed _ids
        uint256[] memory ids = new uint256[](len);
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

        // construct keys
        bytes[][] memory keys = new bytes[][](idsLength);
        for (uint256 i; i < idsLength; ++i) {
            keys[i] = new bytes[](numKeys);
            for (uint256 j; j < numKeys; ++j) {
                keys[i][j] = abi.encodePacked(j);
            }
        }

        vm.prank(admin);
        keyRegistry.bulkAddSignersForMigration(ids, keys);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertEq(keyRegistry.signerOf(ids[i], 1, keys[i][j]).state, KeyRegistry.SignerState.AUTHORIZED);
            }
        }
    }

    function testFuzzBulkAddSignerForMigrationDuringGracePeriod(uint40 _warpForward) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);
        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(admin);

        keyRegistry.migrateSigners();
        vm.warp(keyRegistry.signersMigratedAt() + warpForward);

        keyRegistry.bulkAddSignersForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigrationAfterGracePeriodRevertsUnauthorized(uint40 _warpForward) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);
        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.signersMigratedAt());

        vm.startPrank(admin);

        keyRegistry.migrateSigners();
        vm.warp(keyRegistry.signersMigratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.bulkAddSignersForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigrationRevertsMismatchedInput() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](1);

        vm.startPrank(admin);
        vm.expectRevert(KeyRegistry.InvalidBatchInput.selector);
        keyRegistry.bulkAddSignersForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigration(uint256[] memory _ids, uint8 _numKeys) public {
        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);
        uint256 numKeys = bound(_numKeys, 1, 10);

        // bound and deduplicate fuzzed _ids
        uint256[] memory ids = new uint256[](len);
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

        // construct keys
        bytes[][] memory keys = new bytes[][](idsLength);
        for (uint256 i; i < idsLength; ++i) {
            keys[i] = new bytes[](numKeys);
            for (uint256 j; j < numKeys; ++j) {
                keys[i][j] = abi.encodePacked(j);
            }
        }

        vm.startPrank(admin);

        keyRegistry.bulkAddSignersForMigration(ids, keys);
        keyRegistry.bulkRemoveSignersForMigration(ids, keys);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertEq(keyRegistry.signerOf(ids[i], 1, keys[i][j]).state, KeyRegistry.SignerState.UNINITIALIZED);
            }
        }

        vm.stopPrank();
    }

    function testBulkRemoveEmitsEvent() public {
        uint256[] memory ids = new uint256[](3);
        bytes[][] memory keys = new bytes[][](3);

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

        vm.startPrank(admin);

        keyRegistry.bulkAddSignersForMigration(ids, keys);

        vm.expectEmit();
        emit Remove(ids[0], 1, keys[0][0], keys[0][0]);

        vm.expectEmit();
        emit Remove(ids[1], 1, keys[1][0], keys[1][0]);

        vm.expectEmit();
        emit Remove(ids[2], 1, keys[2][0], keys[2][0]);

        vm.expectEmit();
        emit Remove(ids[2], 1, keys[2][1], keys[2][1]);

        keyRegistry.bulkRemoveSignersForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationDuringGracePeriod(uint40 _warpForward) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);
        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(admin);

        keyRegistry.migrateSigners();
        vm.warp(keyRegistry.signersMigratedAt() + warpForward);

        keyRegistry.bulkRemoveSignersForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationAfterGracePeriodRevertsUnauthorized(uint40 _warpForward) public {
        uint256[] memory ids = new uint256[](1);
        bytes[][] memory keys = new bytes[][](1);

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.signersMigratedAt());

        vm.startPrank(admin);

        keyRegistry.migrateSigners();
        vm.warp(keyRegistry.signersMigratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.bulkRemoveSignersForMigration(ids, keys);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationRevertsMismatchedInput() public {
        uint256[] memory ids = new uint256[](2);
        bytes[][] memory keys = new bytes[][](1);

        vm.startPrank(admin);
        vm.expectRevert(KeyRegistry.InvalidBatchInput.selector);
        keyRegistry.bulkRemoveSignersForMigration(ids, keys);

        vm.stopPrank();
    }

    function _registerFid(address to, address recovery) internal returns (uint256) {
        return idRegistry.register(to, recovery);
    }

    function assertEq(KeyRegistry.SignerState a, KeyRegistry.SignerState b) internal {
        assertEq(uint8(a), uint8(b));
    }
}
