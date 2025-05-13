// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {IdRegistry, IIdRegistry} from "../../src/IdRegistry.sol";

contract IdRegistrySymTest is SymTest, Test {
    IdRegistry idRegistry;
    address migrator;
    address idGateway;
    address x;
    address y;

    function setUp() public {
        idGateway = address(0x1000);
        migrator = address(0x2000);

        // Setup IdRegistry
        idRegistry = new IdRegistry(migrator, address(this));
        idRegistry.setIdGateway(address(idGateway));
        idRegistry.unpause();

        // Register fids
        vm.prank(idGateway);
        idRegistry.register(address(0x1001), address(0x2001));
        vm.prank(idGateway);
        idRegistry.register(address(0x1002), address(0x2002));

        assert(idRegistry.idOf(address(0x1001)) == 1);
        assert(idRegistry.idOf(address(0x1002)) == 2);

        assert(idRegistry.recoveryOf(1) == address(0x2001));
        assert(idRegistry.recoveryOf(2) == address(0x2002));

        // Create symbolic addresses
        x = svm.createAddress("x");
        y = svm.createAddress("y");
    }

    function check_Invariants_PostMigration(bytes4 selector, address caller) public {
        _assumeMigrated();
        _initState();
        vm.assume(x != y);

        // Record pre-state
        uint256 oldIdX = idRegistry.idOf(x);
        uint256 oldIdY = idRegistry.idOf(y);
        uint256 oldIdCounter = idRegistry.idCounter();
        bool oldPaused = idRegistry.paused();

        // Execute an arbitrary tx to IdRegistry
        vm.prank(caller);
        (bool success,) = address(idRegistry).call(_calldataFor(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        uint256 newIdX = idRegistry.idOf(x);
        uint256 newIdY = idRegistry.idOf(y);
        uint256 newIdCounter = idRegistry.idCounter();

        // Ensure that there is no recovery address associated with fid 0.
        assert(idRegistry.recoveryOf(0) == address(0));

        // Ensure that idCounter never decreases.
        assert(newIdCounter >= oldIdCounter);

        // If a new fid is registered, ensure that:
        // - IdRegistry must not be paused.
        // - idCounter must increase by 1.
        // - The new fid must not be registered for an existing fid owner.
        // - The existing fids must be preserved.
        if (newIdCounter > oldIdCounter) {
            assert(oldPaused == false);
            assert(newIdCounter - oldIdCounter == 1);
            assert(newIdX == oldIdX || oldIdX == 0);
            assert(newIdX == oldIdX || newIdY == oldIdY);
        }
    }

    function check_Transfer(address caller, address to, address other) public {
        _initState();
        vm.assume(other != caller && other != to);

        // Record pre-state
        uint256 oldIdCaller = idRegistry.idOf(caller);
        uint256 oldIdTo = idRegistry.idOf(to);
        uint256 oldIdOther = idRegistry.idOf(other);

        // Execute transfer with symbolic arguments
        vm.prank(caller);
        idRegistry.transfer(to, svm.createUint256("deadline"), svm.createBytes(65, "sig"));

        // Record post-state
        uint256 newIdCaller = idRegistry.idOf(caller);
        uint256 newIdTo = idRegistry.idOf(to);
        uint256 newIdOther = idRegistry.idOf(other);

        // Ensure that the fid has been transferred from the `caller` to the `to`.
        assert(newIdTo == oldIdCaller);
        if (caller != to) {
            assert(oldIdCaller != 0 && newIdCaller == 0);
            assert(oldIdTo == 0 && newIdTo != 0);
        }

        // Ensure that the other fids are not affected.
        assert(newIdOther == oldIdOther);
    }

    function check_Recovery(address caller, address from, address to, address other) public {
        _initState();
        vm.assume(other != from && other != to);

        // Record pre-state
        uint256 oldIdFrom = idRegistry.idOf(from);
        uint256 oldIdTo = idRegistry.idOf(to);
        uint256 oldIdOther = idRegistry.idOf(other);
        address oldRecoveryFrom = idRegistry.recoveryOf(oldIdFrom);

        // Execute recover with symbolic arguments
        vm.prank(caller);
        idRegistry.recover(from, to, svm.createUint256("deadline"), svm.createBytes(65, "sig"));

        // Record post-state
        uint256 newIdFrom = idRegistry.idOf(from);
        uint256 newIdTo = idRegistry.idOf(to);
        uint256 newIdOther = idRegistry.idOf(other);

        // Ensure that the caller is the recovery address
        assert(caller == oldRecoveryFrom);

        // Ensure that the fid has been transferred from the `from` to the `to`.
        assert(newIdTo == oldIdFrom);
        if (from != to) {
            assert(oldIdFrom != 0 && newIdFrom == 0);
            assert(oldIdTo == 0 && newIdTo != 0);
        }

        // Ensure that the other fids are not affected.
        assert(newIdOther == oldIdOther);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initialize IdRegistry with symbolic arguments for state.
     */
    function _initState() public {
        if (svm.createBool("pause?")) {
            idRegistry.pause();
        }
    }

    /**
     * @dev Set IdRegistry to post-migration state.
     */
    function _assumeMigrated() public {
        // Pause the IdRegistry, since migrations take place in paused state.
        idRegistry.pause();

        // Complete the migration.
        vm.prank(migrator);
        idRegistry.migrate();

        // Unpause the IdRegistry.
        idRegistry.unpause();

        // Warp to a symbolic timestamp
        vm.warp(svm.createUint(64, "timestamp2"));

        // Assume migration is completed.
        bool migrationCompleted =
            idRegistry.isMigrated() && block.timestamp > idRegistry.migratedAt() + idRegistry.gracePeriod();
        vm.assume(migrationCompleted);
    }

    /**
     * @dev Generates valid calldata for a given function selector.
     */
    function _calldataFor(
        bytes4 selector
    ) internal returns (bytes memory) {
        bytes memory args;
        if (selector == idRegistry.transfer.selector) {
            args = abi.encode(svm.createAddress("to"), svm.createUint256("deadline"), svm.createBytes(65, "sig"));
        } else if (selector == idRegistry.transferFor.selector) {
            args = abi.encode(
                svm.createAddress("from"),
                svm.createAddress("to"),
                svm.createUint256("fromDeadline"),
                svm.createBytes(65, "fromSig"),
                svm.createUint256("toDeadline"),
                svm.createBytes(65, "toSig")
            );
        } else if (selector == idRegistry.transferAndChangeRecovery.selector) {
            args = abi.encode(
                svm.createAddress("to"),
                svm.createAddress("recovery"),
                svm.createUint256("deadline"),
                svm.createBytes(65, "sig")
            );
        } else if (selector == idRegistry.transferAndChangeRecoveryFor.selector) {
            args = abi.encode(
                svm.createAddress("from"),
                svm.createAddress("to"),
                svm.createAddress("recovery"),
                svm.createUint256("fromDeadline"),
                svm.createBytes(65, "fromSig"),
                svm.createUint256("toDeadline"),
                svm.createBytes(65, "toSig")
            );
        } else if (selector == idRegistry.changeRecoveryAddressFor.selector) {
            args = abi.encode(
                svm.createAddress("owner"),
                svm.createAddress("recovery"),
                svm.createUint256("deadline"),
                svm.createBytes(65, "sig")
            );
        } else if (selector == idRegistry.recover.selector) {
            args = abi.encode(
                svm.createAddress("from"),
                svm.createAddress("to"),
                svm.createUint256("deadline"),
                svm.createBytes(65, "sig")
            );
        } else if (selector == idRegistry.recoverFor.selector) {
            args = abi.encode(
                svm.createAddress("from"),
                svm.createAddress("to"),
                svm.createUint256("recoveryDeadline"),
                svm.createBytes(65, "recoverySig"),
                svm.createUint256("toDeadline"),
                svm.createBytes(65, "toSig")
            );
        } else if (selector == idRegistry.verifyFidSignature.selector) {
            args = abi.encode(
                svm.createAddress("custodyAddress"),
                svm.createUint256("fid"),
                svm.createBytes32("digest"),
                svm.createBytes(65, "sig")
            );
        } else if (selector == idRegistry.bulkRegisterIds.selector) {
            IIdRegistry.BulkRegisterData[] memory ids = new IIdRegistry.BulkRegisterData[](0);
            args = abi.encode(ids);
        } else if (selector == idRegistry.bulkRegisterIdsWithDefaultRecovery.selector) {
            IIdRegistry.BulkRegisterDefaultRecoveryData[] memory ids =
                new IIdRegistry.BulkRegisterDefaultRecoveryData[](0);
            args = abi.encode(ids, address(0));
        } else if (selector == idRegistry.bulkResetIds.selector) {
            uint24[] memory ids = new uint24[](0);
            args = abi.encode(ids);
        } else {
            args = svm.createBytes(1024, "data");
        }

        return abi.encodePacked(selector, args);
    }
}
