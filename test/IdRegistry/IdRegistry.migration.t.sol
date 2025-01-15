// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {IdRegistry, IIdRegistry} from "../../src/IdRegistry.sol";
import {IMigration} from "../../src/interfaces/abstract/IMigration.sol";

import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";
import {BulkRegisterDataBuilder, BulkRegisterDefaultRecoveryDataBuilder} from "./IdRegistryTestHelpers.sol";

/* solhint-disable state-visibility */

contract IdRegistryTest is IdRegistryTestSuite {
    using BulkRegisterDataBuilder for IIdRegistry.BulkRegisterData[];
    using BulkRegisterDefaultRecoveryDataBuilder for IIdRegistry.BulkRegisterDefaultRecoveryData[];

    function setUp() public override {
        super.setUp();

        // Pause the IdRegistry. Migrations must take place when paused.
        vm.prank(owner);
        idRegistry.pause();
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);
    event Migrated(uint256 indexed migratedAt);
    event AdminReset(uint256 indexed fid);
    event SetIdCounter(uint256 oldCounter, uint256 newCounter);
    event FreezeIdGateway(address idGateway);
    event SetMigrator(address oldMigrator, address newMigrator);

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testInitialGracePeriod() public {
        assertEq(idRegistry.gracePeriod(), 1 days);
    }

    function testInitialMigrationTimestamp() public {
        assertEq(idRegistry.migratedAt(), 0);
    }

    function testInitialMigrator() public {
        assertEq(idRegistry.migrator(), migrator);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(idRegistry.isMigrated(), false);
    }

    /*//////////////////////////////////////////////////////////////
                             SET MIGRATOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzOwnerCanSetMigrator(
        address migrator
    ) public {
        address oldMigrator = idRegistry.migrator();

        vm.expectEmit();
        emit SetMigrator(oldMigrator, migrator);
        vm.prank(owner);
        idRegistry.setMigrator(migrator);

        assertEq(idRegistry.migrator(), migrator);
    }

    function testFuzzSetMigratorRevertsWhenMigrated(
        address migrator
    ) public {
        address oldMigrator = idRegistry.migrator();

        vm.prank(oldMigrator);
        idRegistry.migrate();

        vm.prank(owner);
        vm.expectRevert(IMigration.AlreadyMigrated.selector);
        idRegistry.setMigrator(migrator);

        assertEq(idRegistry.migrator(), oldMigrator);
    }

    function testFuzzSetMigratorRevertsWhenUnpaused(
        address migrator
    ) public {
        address oldMigrator = idRegistry.migrator();

        vm.startPrank(owner);
        idRegistry.unpause();
        vm.expectRevert("Pausable: not paused");
        idRegistry.setMigrator(migrator);
        vm.stopPrank();

        assertEq(idRegistry.migrator(), oldMigrator);
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
        idRegistry.migrate();

        assertEq(idRegistry.isMigrated(), true);
        assertEq(idRegistry.migratedAt(), timestamp);
    }

    function testFuzzOnlyMigratorCanMigrate(
        address caller
    ) public {
        vm.assume(caller != migrator);

        vm.prank(caller);
        vm.expectRevert(IMigration.OnlyMigrator.selector);
        idRegistry.migrate();

        assertEq(idRegistry.isMigrated(), false);
        assertEq(idRegistry.migratedAt(), 0);
    }

    function testFuzzCannotMigrateTwice(
        uint40 timestamp
    ) public {
        timestamp = uint40(bound(timestamp, 1, type(uint40).max));
        vm.warp(timestamp);
        vm.prank(migrator);
        idRegistry.migrate();

        timestamp = uint40(bound(timestamp, timestamp, type(uint40).max));
        vm.expectRevert(IMigration.AlreadyMigrated.selector);
        vm.prank(migrator);
        idRegistry.migrate();

        assertEq(idRegistry.isMigrated(), true);
        assertEq(idRegistry.migratedAt(), timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          SET COUNTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetIdCounter(
        uint256 idCounter
    ) public {
        uint256 prevIdCounter = idRegistry.idCounter();

        vm.expectEmit();
        emit SetIdCounter(prevIdCounter, idCounter);

        vm.prank(migrator);
        idRegistry.setIdCounter(idCounter);

        assertEq(idRegistry.idCounter(), idCounter);
    }

    function testFuzzSetIdCounterDuringGracePeriod(uint256 idCounter, uint40 _warpForward) public {
        uint256 prevIdCounter = idRegistry.idCounter();
        uint256 warpForward = bound(_warpForward, 1, idRegistry.gracePeriod() - 1);

        vm.prank(migrator);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + warpForward);

        vm.expectEmit();
        emit SetIdCounter(prevIdCounter, idCounter);

        vm.prank(migrator);
        idRegistry.setIdCounter(idCounter);

        assertEq(idRegistry.idCounter(), idCounter);
    }

    function testFuzzSetIdCounterAfterGracePeriodReverts(uint256 idCounter, uint40 _warpForward) public {
        uint256 prevIdCounter = idRegistry.idCounter();
        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - idRegistry.gracePeriod() - idRegistry.migratedAt());

        vm.prank(migrator);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + idRegistry.gracePeriod() + warpForward);

        vm.prank(migrator);
        vm.expectRevert(IMigration.PermissionRevoked.selector);
        idRegistry.setIdCounter(idCounter);

        assertEq(idRegistry.idCounter(), prevIdCounter);
    }

    function testFuzzSetIdCounterUnpausedReverts(
        uint256 idCounter
    ) public {
        uint256 prevIdCounter = idRegistry.idCounter();

        vm.prank(owner);
        idRegistry.unpause();

        vm.prank(migrator);
        vm.expectRevert("Pausable: not paused");
        idRegistry.setIdCounter(idCounter);

        assertEq(idRegistry.idCounter(), prevIdCounter);
    }

    /*//////////////////////////////////////////////////////////////
                            BULK REGISTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzBulkRegisterIds(uint24[] memory _ids, uint128 toSeed, uint128 recoverySeed) public {
        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);

        uint24[] memory ids = _dedupeFuzzedIds(_ids, len);
        uint256 idsLength = ids.length;
        IIdRegistry.BulkRegisterData[] memory registerItems = _buildRegisterData(ids, toSeed, recoverySeed);

        vm.prank(migrator);
        idRegistry.bulkRegisterIds(registerItems);

        for (uint256 i; i < idsLength; ++i) {
            IIdRegistry.BulkRegisterData memory item = registerItems[i];
            assertEq(idRegistry.idCounter(), 0);
            assertEq(idRegistry.idOf(item.custody), item.fid);
            assertEq(idRegistry.custodyOf(item.fid), item.custody);
            assertEq(idRegistry.recoveryOf(item.fid), item.recovery);
        }
    }

    function testBulkRegisterEmitsEvent() public {
        IIdRegistry.BulkRegisterData[] memory registerItems =
            BulkRegisterDataBuilder.empty().addFid(1).addFid(2).addFid(3);

        for (uint256 i; i < 3; i++) {
            IIdRegistry.BulkRegisterData memory item = registerItems[i];
            vm.expectEmit();
            emit Register(item.custody, item.fid, item.recovery);
        }

        vm.prank(migrator);
        idRegistry.bulkRegisterIds(registerItems);
    }

    function testFuzzBulkRegisterDuringGracePeriod(
        uint40 _warpForward
    ) public {
        IdRegistry.BulkRegisterData[] memory registerItems = BulkRegisterDataBuilder.empty().addFid(1);

        uint256 warpForward = bound(_warpForward, 1, idRegistry.gracePeriod() - 1);

        vm.startPrank(migrator);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + warpForward);

        idRegistry.bulkRegisterIds(registerItems);
        vm.stopPrank();
    }

    function testFuzzBulkRegisterAfterGracePeriodRevertsUnauthorized(
        uint40 _warpForward
    ) public {
        IdRegistry.BulkRegisterData[] memory registerItems = BulkRegisterDataBuilder.empty().addFid(1);

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - idRegistry.gracePeriod() - idRegistry.migratedAt());

        vm.startPrank(migrator);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + idRegistry.gracePeriod() + warpForward);

        vm.expectRevert(IMigration.PermissionRevoked.selector);
        idRegistry.bulkRegisterIds(registerItems);
        vm.stopPrank();
    }

    function testBulkRegisterCannotReRegister() public {
        IdRegistry.BulkRegisterData[] memory registerItems =
            BulkRegisterDataBuilder.empty().addFid(1).addFid(2).addFid(3);

        vm.startPrank(migrator);
        idRegistry.bulkRegisterIds(registerItems);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idRegistry.bulkRegisterIds(registerItems);
        vm.stopPrank();
    }

    function testBulkRegisterUnpausedReverts() public {
        IdRegistry.BulkRegisterData[] memory registerItems =
            BulkRegisterDataBuilder.empty().addFid(1).addFid(2).addFid(3);

        vm.prank(owner);
        idRegistry.unpause();

        vm.prank(migrator);
        vm.expectRevert("Pausable: not paused");
        idRegistry.bulkRegisterIds(registerItems);
    }

    /*//////////////////////////////////////////////////////////////
                BULK REGISTER WITH DEFAULT RECOVERY
    //////////////////////////////////////////////////////////////*/

    function testFuzzBulkRegisterIdsWithRecovery(uint24[] memory _ids, uint128 toSeed, address recovery) public {
        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);

        uint24[] memory ids = _dedupeFuzzedIds(_ids, len);
        uint256 idsLength = ids.length;
        IIdRegistry.BulkRegisterDefaultRecoveryData[] memory registerItems =
            _buildRegisterWithDefaultRecoveryData(ids, toSeed);

        vm.prank(migrator);
        idRegistry.bulkRegisterIdsWithDefaultRecovery(registerItems, recovery);

        for (uint256 i; i < idsLength; ++i) {
            IIdRegistry.BulkRegisterDefaultRecoveryData memory item = registerItems[i];
            assertEq(idRegistry.idCounter(), 0);
            assertEq(idRegistry.idOf(item.custody), item.fid);
            assertEq(idRegistry.custodyOf(item.fid), item.custody);
            assertEq(idRegistry.recoveryOf(item.fid), recovery);
        }
    }

    function testBulkRegisterWithRecoveryEmitsEvent(
        address recovery
    ) public {
        IIdRegistry.BulkRegisterDefaultRecoveryData[] memory registerItems =
            BulkRegisterDefaultRecoveryDataBuilder.empty().addFid(1).addFid(2).addFid(3);

        for (uint256 i; i < 3; i++) {
            IIdRegistry.BulkRegisterDefaultRecoveryData memory item = registerItems[i];
            vm.expectEmit();
            emit Register(item.custody, item.fid, recovery);
        }

        vm.prank(migrator);
        idRegistry.bulkRegisterIdsWithDefaultRecovery(registerItems, recovery);
    }

    function testFuzzBulkRegisterWithRecoveryDuringGracePeriod(uint40 _warpForward, address recovery) public {
        IdRegistry.BulkRegisterDefaultRecoveryData[] memory registerItems =
            BulkRegisterDefaultRecoveryDataBuilder.empty().addFid(1);

        uint256 warpForward = bound(_warpForward, 1, idRegistry.gracePeriod() - 1);

        vm.startPrank(migrator);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + warpForward);

        idRegistry.bulkRegisterIdsWithDefaultRecovery(registerItems, recovery);
        vm.stopPrank();
    }

    function testFuzzBulkRegisterWithRecoveryAfterGracePeriodRevertsUnauthorized(
        uint40 _warpForward,
        address recovery
    ) public {
        IdRegistry.BulkRegisterDefaultRecoveryData[] memory registerItems =
            BulkRegisterDefaultRecoveryDataBuilder.empty().addFid(1);

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - idRegistry.gracePeriod() - idRegistry.migratedAt());

        vm.startPrank(migrator);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + idRegistry.gracePeriod() + warpForward);

        vm.expectRevert(IMigration.PermissionRevoked.selector);
        idRegistry.bulkRegisterIdsWithDefaultRecovery(registerItems, recovery);
        vm.stopPrank();
    }

    function testBulkRegisterWithRecoveryCannotReRegister(
        address recovery
    ) public {
        IdRegistry.BulkRegisterDefaultRecoveryData[] memory registerItems =
            BulkRegisterDefaultRecoveryDataBuilder.empty().addFid(1).addFid(2).addFid(3);

        vm.startPrank(migrator);
        idRegistry.bulkRegisterIdsWithDefaultRecovery(registerItems, recovery);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idRegistry.bulkRegisterIdsWithDefaultRecovery(registerItems, recovery);
        vm.stopPrank();
    }

    function testBulkRegisterWithRecoveryUnpausedReverts(
        address recovery
    ) public {
        IdRegistry.BulkRegisterDefaultRecoveryData[] memory registerItems =
            BulkRegisterDefaultRecoveryDataBuilder.empty().addFid(1).addFid(2).addFid(3);

        vm.prank(owner);
        idRegistry.unpause();

        vm.prank(migrator);
        vm.expectRevert("Pausable: not paused");
        idRegistry.bulkRegisterIdsWithDefaultRecovery(registerItems, recovery);
    }

    /*//////////////////////////////////////////////////////////////
                            BULK RESET
    //////////////////////////////////////////////////////////////*/

    function testFuzzBulkResetIds(
        uint24[] memory _ids
    ) public {
        vm.assume(_ids.length > 0);
        uint256 len = bound(_ids.length, 1, 100);

        uint24[] memory ids = _dedupeFuzzedIds(_ids, len);
        uint256 idsLength = ids.length;

        IIdRegistry.BulkRegisterData[] memory registerItems = BulkRegisterDataBuilder.empty();
        uint24[] memory resetItems = new uint24[](idsLength);

        for (uint256 i; i < idsLength; ++i) {
            registerItems = registerItems.addFid(ids[i]);
            resetItems[i] = ids[i];
        }
        vm.startPrank(migrator);

        idRegistry.bulkRegisterIds(registerItems);
        idRegistry.bulkResetIds(resetItems);

        for (uint256 i; i < idsLength; ++i) {
            IIdRegistry.BulkRegisterData memory item = registerItems[i];
            assertEq(idRegistry.idCounter(), 0);
            assertEq(idRegistry.idOf(item.custody), 0);
            assertEq(idRegistry.custodyOf(item.fid), address(0));
            assertEq(idRegistry.recoveryOf(item.fid), address(0));
        }

        vm.stopPrank();
    }

    function testBulkResetEmitsEvent() public {
        IdRegistry.BulkRegisterData[] memory registerItems =
            BulkRegisterDataBuilder.empty().addFid(1).addFid(2).addFid(3);
        uint24[] memory resetItems = new uint24[](3);

        vm.prank(migrator);
        idRegistry.bulkRegisterIds(registerItems);

        for (uint256 i; i < 3; i++) {
            IdRegistry.BulkRegisterData memory item = registerItems[i];
            resetItems[i] = item.fid;
            vm.expectEmit();
            emit AdminReset(item.fid);
        }

        vm.prank(migrator);
        idRegistry.bulkResetIds(resetItems);
    }

    function testFuzzBulkResetDuringGracePeriod(
        uint40 _warpForward
    ) public {
        IdRegistry.BulkRegisterData[] memory registerItems =
            BulkRegisterDataBuilder.empty().addFid(1).addFid(2).addFid(3);
        uint24[] memory resetItems = new uint24[](3);

        for (uint256 i; i < registerItems.length; i++) {
            IdRegistry.BulkRegisterData memory item = registerItems[i];
            resetItems[i] = item.fid;
        }

        uint256 warpForward = bound(_warpForward, 1, idRegistry.gracePeriod() - 1);

        vm.startPrank(migrator);
        idRegistry.bulkRegisterIds(registerItems);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + warpForward);

        idRegistry.bulkResetIds(resetItems);
        vm.stopPrank();
    }

    function testFuzzBulkResetAfterGracePeriodRevertsUnauthorized(
        uint40 _warpForward
    ) public {
        uint24[] memory resetItems = new uint24[](3);

        uint256 warpForward =
            bound(_warpForward, 1, type(uint40).max - idRegistry.gracePeriod() - idRegistry.migratedAt());

        vm.startPrank(migrator);
        idRegistry.migrate();

        vm.warp(idRegistry.migratedAt() + idRegistry.gracePeriod() + warpForward);

        vm.expectRevert(IMigration.PermissionRevoked.selector);
        idRegistry.bulkResetIds(resetItems);

        vm.stopPrank();
    }

    function testFuzzBulkResetUnpausedReverts() public {
        uint24[] memory resetItems = new uint24[](3);

        vm.prank(owner);
        idRegistry.unpause();

        vm.prank(migrator);
        vm.expectRevert("Pausable: not paused");
        idRegistry.bulkResetIds(resetItems);
    }

    function _dedupeFuzzedIds(uint24[] memory _ids, uint256 len) internal pure returns (uint24[] memory ids) {
        ids = new uint24[](len);
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

    function _buildRegisterData(
        uint24[] memory fids,
        uint128 toSeed,
        uint128 recoverySeed
    ) internal pure returns (IIdRegistry.BulkRegisterData[] memory) {
        IIdRegistry.BulkRegisterData[] memory registerItems = new IIdRegistry.BulkRegisterData[](fids.length);
        for (uint256 i; i < fids.length; ++i) {
            registerItems[i] = IIdRegistry.BulkRegisterData({
                fid: fids[i],
                custody: vm.addr(uint256(keccak256(abi.encodePacked(toSeed + i)))),
                recovery: vm.addr(uint256(keccak256(abi.encodePacked(recoverySeed + i))))
            });
        }
        return registerItems;
    }

    function _buildRegisterWithDefaultRecoveryData(
        uint24[] memory fids,
        uint128 toSeed
    ) internal pure returns (IIdRegistry.BulkRegisterDefaultRecoveryData[] memory) {
        IIdRegistry.BulkRegisterDefaultRecoveryData[] memory registerItems =
            new IIdRegistry.BulkRegisterDefaultRecoveryData[](fids.length);
        for (uint256 i; i < fids.length; ++i) {
            registerItems[i] = IIdRegistry.BulkRegisterDefaultRecoveryData({
                fid: fids[i],
                custody: vm.addr(uint256(keccak256(abi.encodePacked(toSeed + i))))
            });
        }
        return registerItems;
    }
}
