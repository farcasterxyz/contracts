// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {KeyRegistry, IKeyRegistry} from "../../src/KeyRegistry.sol";
import {IGuardians} from "../../src/lib/Guardians.sol";
import {ISignatures} from "../../src/lib/Signatures.sol";
import {IMigration} from "../../src/lib/Migration.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";

import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";
import {BulkAddDataBuilder, BulkResetDataBuilder} from "./KeyRegistryTestHelpers.sol";

/* solhint-disable state-visibility */

contract KeyRegistryTest is KeyRegistryTestSuite {
    using BulkAddDataBuilder for KeyRegistry.BulkAddData[];
    using BulkResetDataBuilder for KeyRegistry.BulkResetData[];

    function setUp() public override {
        super.setUp();
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
    event SetValidator(uint32 keyType, uint8 metadataType, address oldValidator, address newValidator);
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);
    event SetKeyGateway(address oldKeyGateway, address newKeyGateway);
    event SetMaxKeysPerFid(uint256 oldMax, uint256 newMax);
    event FreezeKeyGateway(address keyGateway);

    function testInitialIdRegistry() public {
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
    }

    function testInitialGracePeriod() public {
        assertEq(keyRegistry.gracePeriod(), 1 days);
    }

    function testInitialMigrationTimestamp() public {
        assertEq(keyRegistry.migratedAt(), 0);
    }

    function testInitialMigrator() public {
        assertEq(keyRegistry.migrator(), owner);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(keyRegistry.isMigrated(), false);
    }

    function testInitialOwner() public {
        assertEq(keyRegistry.owner(), owner);
    }

    function testVersion() public {
        assertEq(keyRegistry.VERSION(), "2023.10.04");
    }

    /*//////////////////////////////////////////////////////////////
                                   ADD
    //////////////////////////////////////////////////////////////*/

    function testFuzzAdd(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        assertEq(keyRegistry.totalKeys(fid), 0);

        vm.expectEmit();
        emit Add(fid, keyType, key, key, metadataType, metadata);
        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        assertEq(keyRegistry.totalKeys(fid), 1);
        assertAdded(fid, key, keyType);
    }

    function testFuzzAddRevertsUnregisteredValidator(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(abi.encodeWithSelector(IKeyRegistry.ValidatorNotFound.selector, keyType, metadataType));
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsInvalidMetadata(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerValidator(keyType, metadataType);

        stubValidator.setIsValid(false);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.InvalidMetadata.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsUnlessRegistration(
        address to,
        address recovery,
        address caller,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        vm.assume(keyRegistry.keyGateway() != caller);
        _registerValidator(keyType, metadataType);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(caller);
        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsIfStateNotNull(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.startPrank(keyRegistry.keyGateway());

        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.stopPrank();
        assertAdded(fid, key, keyType);
    }

    function testFuzzAddRevertsIfRemoved(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.prank(to);
        keyRegistry.remove(key);

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        assertRemoved(fid, key, keyType);
    }

    function testFuzzAddRevertsPaused(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.pause();

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert("Pausable: paused");
        keyRegistry.add(to, keyType, key, metadataType, metadata);
    }

    function testFuzzAddRevertsMaxKeys(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        // Create 10 keys
        for (uint256 i; i < 10; i++) {
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, bytes.concat(key, bytes32(i)), metadataType, metadata);
        }

        // 11th key reverts
        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.ExceedsMaximum.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);
    }

    /*//////////////////////////////////////////////////////////////
                                 REMOVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRemove(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
        assertEq(keyRegistry.totalKeys(fid), 1);

        vm.expectEmit();
        emit Remove(fid, key, key);
        vm.prank(to);
        keyRegistry.remove(key);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
        assertEq(keyRegistry.totalKeys(fid), 0);

        assertRemoved(fid, key, keyType);
    }

    function testFuzzRemoveRevertsUnlessFidOwner(
        address to,
        address recovery,
        address caller,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        vm.assume(to != caller);
        _registerValidator(keyType, metadataType);

        uint256 fid = _registerFid(to, recovery);
        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.remove(key);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveRevertsIfNull(address to, address recovery, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        vm.prank(to);
        keyRegistry.remove(key);

        assertNull(fid, key);
    }

    function testFuzzRemoveRevertsIfRemoved(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.startPrank(to);
        keyRegistry.remove(key);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.remove(key);

        vm.stopPrank();
        assertRemoved(fid, key, keyType);
    }

    function testFuzzRemoveRevertsWhenPaused(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.prank(to);
        keyRegistry.remove(key);

        vm.prank(owner);
        keyRegistry.pause();

        vm.prank(to);
        vm.expectRevert("Pausable: paused");
        keyRegistry.remove(key);

        assertRemoved(fid, key, keyType);
    }

    function testFuzzRemoveFor(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.expectEmit();
        emit Remove(fid, key, key);
        vm.prank(registrar);
        keyRegistry.removeFor(owner, key, deadline, sig);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        assertRemoved(fid, key, keyType);
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
        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);
    }

    function testFuzzRemoveForRevertsInvalidSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline + 1);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsUsedNonce(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(owner);
        keyRegistry.useNonce();

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsBadSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsExpiredSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsWhenPaused(
        address registrar,
        uint256 fidOwnerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        fidOwnerPk = _boundPk(fidOwnerPk);
        _registerValidator(keyType, metadataType);

        address fidOwner = vm.addr(fidOwnerPk);
        uint256 fid = _registerFid(fidOwner, recovery);
        bytes memory sig = _signRemove(fidOwnerPk, fidOwner, key, deadline);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(fidOwner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(owner);
        keyRegistry.pause();

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        keyRegistry.removeFor(fidOwner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testRemoveTypeHash() public {
        assertEq(
            keyRegistry.REMOVE_TYPEHASH(), keccak256("Remove(address owner,bytes key,uint256 nonce,uint256 deadline)")
        );
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
        keyRegistry.migrate();

        assertEq(keyRegistry.isMigrated(), true);
        assertEq(keyRegistry.migratedAt(), timestamp);
    }

    function testFuzzOnlyOwnerCanMigrate(address caller) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IMigration.OnlyMigrator.selector);
        keyRegistry.migrate();

        assertEq(keyRegistry.isMigrated(), false);
        assertEq(keyRegistry.migratedAt(), 0);
    }

    function testFuzzCannotMigrateTwice(uint40 timestamp) public {
        timestamp = uint40(bound(timestamp, 1, type(uint40).max));
        vm.warp(timestamp);
        vm.prank(owner);
        keyRegistry.migrate();

        timestamp = uint40(bound(timestamp, timestamp, type(uint40).max));
        vm.expectRevert(IMigration.AlreadyMigrated.selector);
        vm.prank(owner);
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

        vm.prank(owner);
        keyRegistry.bulkAddKeysForMigration(addItems);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertAdded(ids[i], keys[i][j], 1);
            }
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

        vm.prank(owner);
        keyRegistry.bulkAddKeysForMigration(addItems);
    }

    function testFuzzBulkAddKeyForMigrationDuringGracePeriod(uint40 _warpForward) public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1");

        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(owner);

        keyRegistry.migrate();
        vm.warp(keyRegistry.migratedAt() + warpForward);

        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.stopPrank();
    }

    function testFuzzBulkAddSignerForMigrationAfterGracePeriodRevertsUnauthorized(uint40 _warpForward) public {
        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1");

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.migratedAt());

        vm.startPrank(owner);

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

        vm.startPrank(owner);

        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.bulkAddKeysForMigration(addItems);

        vm.stopPrank();
    }

    function testBulkAddRevertsWhenPaused() public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems =
            BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1").addFid(2).addKey(1, "key2", "metadata2");

        vm.startPrank(owner);
        keyRegistry.pause();

        vm.expectRevert("Pausable: paused");
        keyRegistry.bulkAddKeysForMigration(addItems);
        vm.stopPrank();
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

        vm.startPrank(owner);

        keyRegistry.bulkAddKeysForMigration(addItems);
        keyRegistry.bulkResetKeysForMigration(resetItems);

        for (uint256 i; i < idsLength; ++i) {
            for (uint256 j; j < numKeys; ++j) {
                assertNull(ids[i], keys[i][j]);
            }
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

        vm.startPrank(owner);

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
        vm.prank(owner);
        keyRegistry.bulkResetKeysForMigration(resetItems);
    }

    function testBulkResetRevertsIfRunTwice() public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems =
            BulkAddDataBuilder.empty().addFid(1).addKey(0, "key1", "metadata1").addFid(2).addKey(1, "key2", "metadata2");

        KeyRegistry.BulkResetData[] memory resetItems =
            BulkResetDataBuilder.empty().addFid(1).addKey(0, "key1").addFid(2).addKey(1, "key2");

        vm.startPrank(owner);

        keyRegistry.bulkAddKeysForMigration(addItems);
        keyRegistry.bulkResetKeysForMigration(resetItems);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.bulkResetKeysForMigration(resetItems);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationDuringGracePeriod(uint40 _warpForward) public {
        _registerValidator(1, 1);

        KeyRegistry.BulkAddData[] memory addItems = BulkAddDataBuilder.empty().addFid(1).addKey(0, "key", "metadata");

        KeyRegistry.BulkResetData[] memory resetItems = BulkResetDataBuilder.empty().addFid(1).addKey(0, "key");

        uint256 warpForward = bound(_warpForward, 1, keyRegistry.gracePeriod() - 1);

        vm.startPrank(owner);

        keyRegistry.bulkAddKeysForMigration(addItems);
        keyRegistry.migrate();
        vm.warp(keyRegistry.migratedAt() + warpForward);

        keyRegistry.bulkResetKeysForMigration(resetItems);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationAfterGracePeriodRevertsUnauthorized(uint40 _warpForward) public {
        KeyRegistry.BulkResetData[] memory items = BulkResetDataBuilder.empty().addFid(1).addKey(0, "key");

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - keyRegistry.gracePeriod() - keyRegistry.migratedAt());

        vm.startPrank(owner);

        keyRegistry.migrate();
        vm.warp(keyRegistry.migratedAt() + keyRegistry.gracePeriod() + warpForward);

        vm.expectRevert(IMigration.PermissionRevoked.selector);
        keyRegistry.bulkResetKeysForMigration(items);

        vm.stopPrank();
    }

    function testFuzzBulkRemoveSignerForMigrationRevertsWhenPaused() public {
        KeyRegistry.BulkResetData[] memory items = BulkResetDataBuilder.empty().addFid(1).addKey(0, "key");

        vm.startPrank(owner);
        keyRegistry.pause();

        vm.expectRevert("Pausable: paused");
        keyRegistry.bulkResetKeysForMigration(items);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanPause(address caller) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IGuardians.OnlyGuardian.selector);
        keyRegistry.pause();
    }

    function testPauseUnpause() public {
        assertEq(keyRegistry.paused(), false);

        vm.prank(owner);
        keyRegistry.pause();

        assertEq(keyRegistry.paused(), true);

        vm.prank(owner);
        keyRegistry.unpause();

        assertEq(keyRegistry.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                           SET IDREGISTRY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetIdRegistry(address caller, address idRegistry) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setIdRegistry(idRegistry);
    }

    function testFuzzSetIdRegistry(address idRegistry) public {
        address currentIdRegistry = address(keyRegistry.idRegistry());

        vm.expectEmit(false, false, false, true);
        emit SetIdRegistry(currentIdRegistry, idRegistry);

        vm.prank(owner);
        keyRegistry.setIdRegistry(idRegistry);

        assertEq(address(keyRegistry.idRegistry()), idRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                           SET VALIDATOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetValidator(
        address caller,
        uint32 keyType,
        uint8 metadataType,
        IMetadataValidator validator
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setValidator(keyType, metadataType, validator);
    }

    function testFuzzSetValidatorRevertsZeroKeyType(uint8 metadataType, IMetadataValidator validator) public {
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));
        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.InvalidKeyType.selector);
        keyRegistry.setValidator(0, metadataType, validator);
    }

    function testFuzzSetValidatorRevertsZeroMetadataType(uint32 keyType, IMetadataValidator validator) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.InvalidMetadataType.selector);
        keyRegistry.setValidator(keyType, 0, validator);
    }

    function testFuzzSetValidator(uint32 keyType, uint8 metadataType, IMetadataValidator validator) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        assertEq(address(keyRegistry.validators(keyType, metadataType)), address(0));

        vm.expectEmit(false, false, false, true);
        emit SetValidator(keyType, metadataType, address(0), address(validator));

        vm.prank(owner);
        keyRegistry.setValidator(keyType, metadataType, validator);

        assertEq(address(keyRegistry.validators(keyType, metadataType)), address(validator));
    }

    /*//////////////////////////////////////////////////////////////
                           SET MAX KEYS PER FID
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetMaxKeysPerFid(address caller, uint256 newMax) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setMaxKeysPerFid(newMax);
    }

    function testFuzzSetMaxKeysPerFid(uint256 newMax) public {
        uint256 currentMax = keyRegistry.maxKeysPerFid();
        newMax = bound(newMax, currentMax + 1, type(uint256).max);

        vm.expectEmit(false, false, false, true);
        emit SetMaxKeysPerFid(currentMax, newMax);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(newMax);

        assertEq(keyRegistry.maxKeysPerFid(), newMax);
    }

    function testFuzzSetMaxKeysPerFidRevertsLessThanOrEqualToCurrentMax(uint256 newMax) public {
        uint256 currentMax = keyRegistry.maxKeysPerFid();
        newMax = bound(newMax, 0, currentMax);

        vm.expectRevert(IKeyRegistry.InvalidMaxKeys.selector);
        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(newMax);

        assertEq(keyRegistry.maxKeysPerFid(), currentMax);
    }

    /*//////////////////////////////////////////////////////////////
                           SET KEY GATEWAY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetKeyGateway(address caller, address keyGateway) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setKeyGateway(keyGateway);
    }

    function testFuzzSetKeyGateway(address keyGateway) public {
        address currentKeyGateway = address(keyRegistry.keyGateway());

        vm.expectEmit(false, false, false, true);
        emit SetKeyGateway(currentKeyGateway, keyGateway);

        vm.prank(owner);
        keyRegistry.setKeyGateway(keyGateway);

        assertEq(address(keyRegistry.keyGateway()), keyGateway);
    }

    function testFuzzSetKeyGatewayRevertsWhenFrozen(address keyGateway) public {
        address currentKeyGateway = address(keyRegistry.keyGateway());

        vm.prank(owner);
        keyRegistry.freezeKeyGateway();

        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.GatewayFrozen.selector);
        keyRegistry.setKeyGateway(keyGateway);

        assertEq(address(keyRegistry.keyGateway()), currentKeyGateway);
    }

    function testFreezeKeyGatewayRevertsWhenFrozen() public {
        vm.prank(owner);
        keyRegistry.freezeKeyGateway();

        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.GatewayFrozen.selector);
        keyRegistry.freezeKeyGateway();
    }

    function testOnlyOwnerCanFreezeKeyGateway(address caller) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.freezeKeyGateway();
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
        assertEq(keyRegistry.totalKeys(fid), 0);
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
