// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {IKeyRegistry} from "../../src/interfaces/IKeyRegistry.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";
import {KeyRegistryHarness} from "./utils/KeyRegistryHarness.sol";
import {IdRegistry} from "../../src/IdRegistry.sol";
import {StubValidator} from "../Utils.sol";

contract KeyRegistrySymTest is SymTest, Test {
    IdRegistry idRegistry;
    address idRegistration;

    KeyRegistryHarness keyRegistry;
    StubValidator validator;
    address keyGateway;
    address migrator;

    uint256 x;
    bytes xkey;

    function setUp() public {
        // Setup metadata validator
        validator = new StubValidator();
        idRegistration = address(0x1000);

        migrator = address(0x2000);

        // Setup IdRegistry
        idRegistry = new IdRegistry(migrator, address(this));
        idRegistry.setIdGateway(address(idRegistration));
        idRegistry.unpause();

        // Register fids
        vm.prank(idRegistration);
        idRegistry.register(address(0x1001), address(0x2001));
        vm.prank(idRegistration);
        idRegistry.register(address(0x1002), address(0x2002));
        vm.prank(idRegistration);
        idRegistry.register(address(0x1003), address(0x2003));

        assert(idRegistry.idOf(address(0x1001)) == 1);
        assert(idRegistry.idOf(address(0x1002)) == 2);
        assert(idRegistry.idOf(address(0x1003)) == 3);

        assert(idRegistry.recoveryOf(1) == address(0x2001));
        assert(idRegistry.recoveryOf(2) == address(0x2002));
        assert(idRegistry.recoveryOf(3) == address(0x2003));

        keyGateway = address(0x3000);

        // Setup KeyRegistry
        keyRegistry = new KeyRegistryHarness(address(idRegistry), migrator, address(this), 1000);
        keyRegistry.setValidator(1, 1, IMetadataValidator(address(validator)));
        keyRegistry.setKeyGateway(keyGateway);
        keyRegistry.unpause();

        // Set initial states:
        // - fid 1: removed
        // - fid 2: added
        // - fid 3: null

        bytes memory key1 = svm.createBytes(32, "key1");
        vm.prank(keyGateway);
        keyRegistry.add(address(0x1001), 1, key1, 1, "");
        vm.prank(address(0x1001));
        keyRegistry.remove(key1);
        assert(keyRegistry.keyDataOf(1, key1).state == IKeyRegistry.KeyState.REMOVED);

        bytes memory key2 = svm.createBytes(32, "key2");
        vm.prank(keyGateway);
        keyRegistry.add(address(0x1002), 1, key2, 1, "");
        assert(keyRegistry.keyDataOf(2, key2).state == IKeyRegistry.KeyState.ADDED);

        // Create symbolic fid and key
        x = svm.createUint256("x");
        xkey = svm.createBytes(32, "xkey");
    }

    // Verify the KeyRegistry invariants
    function check_Invariants(bytes4 selector, address caller) public {
        // Additional setup to cover various input states
        if (svm.createBool("migrate?")) {
            vm.prank(migrator);
            keyRegistry.migrate();
        }
        /* NOTE: these configurations don't make any differences for the current KeyRegistry behaviors.
        if (svm.createBool("pause?")) {
            idRegistry.pause();
        }
        */
        vm.warp(svm.createUint(64, "timestamp2"));

        address user = svm.createAddress("user");

        // Record pre-state
        IKeyRegistry.KeyState oldStateX = keyRegistry.keyDataOf(x, xkey).state;

        uint256 oldCallerId = idRegistry.idOf(caller);

        uint256 oldUserId = idRegistry.idOf(user);

        bool isNotMigratedOrGracePeriod =
            !keyRegistry.isMigrated() || block.timestamp <= keyRegistry.migratedAt() + keyRegistry.gracePeriod();

        // Execute an arbitrary tx to KeyRegistry
        vm.prank(caller);
        (bool success,) = address(keyRegistry).call(mk_calldata(selector, user));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        IKeyRegistry.KeyState newStateX = keyRegistry.keyDataOf(x, xkey).state;

        // Verify invariant properties

        if (newStateX != oldStateX) {
            // If the state of fid x is changed by any transaction to KeyRegistry,
            // ensure that the state transition satisfies the following properties.

            // Ensure that the REMOVED state does not allow any state transitions.
            assert(oldStateX != IKeyRegistry.KeyState.REMOVED);

            if (newStateX == IKeyRegistry.KeyState.REMOVED) {
                // For a transition to REMOVED, ensure that:
                // - The previous state must be ADD.
                assert(oldStateX == IKeyRegistry.KeyState.ADDED);
                // - The transition can only be made by remove() or removeFor()
                if (selector == keyRegistry.remove.selector) {
                    //   - remove() must be called by the owner of fid x.
                    assert(oldCallerId == x);
                } else if (selector == keyRegistry.removeFor.selector) {
                    //   - removeFor() makes the transition for the given fidOwner.
                    assert(oldUserId == x);
                } else {
                    assert(false);
                }
            } else if (newStateX == IKeyRegistry.KeyState.ADDED) {
                // For a transition to ADDED, ensure that:
                // - The previous state must be NULL.
                // - The transition can only be made by add() or bulkAddKeysForMigration()
                assert(oldStateX == IKeyRegistry.KeyState.NULL);
                if (selector == keyRegistry.add.selector) {
                    //   - add() must be called by the key manager contract.
                    assert(caller == keyGateway);
                } else if (selector == keyRegistry.bulkAddKeysForMigration.selector) {
                    //   - bulkAdd() must be called by the owner of KeyRegistry.
                    //   - bulkAdd() must be called before the key migration or within the grade period following the migration.
                    assert(caller == migrator); // `this` is the owner of KeyRegistry
                    assert(isNotMigratedOrGracePeriod);
                } else {
                    assert(false);
                }
            } else if (newStateX == IKeyRegistry.KeyState.NULL) {
                // For a transition to NULL, ensure that:
                // - The previous state must be ADDED.
                // - The transition can only be made by bulkReset(), where:
                //   - It must be called by the owner of KeyRegistry.
                //   - It must be called before the key migration or within the grade period following the migration.
                assert(oldStateX == IKeyRegistry.KeyState.ADDED);
                assert(selector == keyRegistry.bulkResetKeysForMigration.selector);
                assert(caller == migrator); // `this` is the owner of KeyRegistry
                assert(isNotMigratedOrGracePeriod);
            } else {
                // Ensure that no other state transitions are possible.
                assert(false);
            }
        }
    }

    // Case-splitting tactic: explicitly branching into two states: cond vs !cond
    function split_cases(
        bool cond
    ) internal pure {
        if (cond) return;
    }

    function mk_calldata(bytes4 selector, address user) internal returns (bytes memory) {
        // Ignore view functions
        vm.assume(selector != keyRegistry.REMOVE_TYPEHASH.selector);
        vm.assume(selector != keyRegistry.VERSION.selector);
        vm.assume(selector != keyRegistry.eip712Domain.selector);
        vm.assume(selector != keyRegistry.gatewayFrozen.selector);
        vm.assume(selector != keyRegistry.gracePeriod.selector);
        vm.assume(selector != keyRegistry.guardians.selector);
        vm.assume(selector != keyRegistry.idRegistry.selector);
        vm.assume(selector != keyRegistry.isMigrated.selector);
        vm.assume(selector != keyRegistry.keyAt.selector);
        vm.assume(selector != keyRegistry.keyDataOf.selector);
        vm.assume(selector != keyRegistry.keyGateway.selector);
        vm.assume(selector != keyRegistry.keys.selector);
        vm.assume(selector != bytes4(0x1f64222f)); // keysOf
        vm.assume(selector != bytes4(0xf27995e3)); // keysOf paged
        vm.assume(selector != keyRegistry.maxKeysPerFid.selector);
        vm.assume(selector != keyRegistry.migratedAt.selector);
        vm.assume(selector != keyRegistry.migrator.selector);
        vm.assume(selector != keyRegistry.nonces.selector);
        vm.assume(selector != keyRegistry.owner.selector);
        vm.assume(selector != keyRegistry.paused.selector);
        vm.assume(selector != keyRegistry.pendingOwner.selector);
        vm.assume(selector != keyRegistry.totalKeys.selector);
        vm.assume(selector != keyRegistry.validators.selector);

        // Create symbolic values to be included in calldata
        uint256 fid = svm.createUint256("fid");
        uint32 keyType = uint32(svm.createUint(32, "keyType"));
        bytes memory key = svm.createBytes(32, "key");
        uint8 metadataType = uint8(svm.createUint(8, "metadataType"));
        bytes memory metadata = svm.createBytes(32, "metadata");
        uint256 deadline = svm.createUint256("deadline");
        bytes memory sig = svm.createBytes(65, "sig");

        // Halmos requires symbolic dynamic arrays to be given with a specific size.
        // In this test, we provide arrays with length 2.
        IKeyRegistry.BulkAddData[] memory addData = new IKeyRegistry.BulkAddData[](2);
        IKeyRegistry.BulkResetData[] memory resetData = new IKeyRegistry.BulkResetData[](2);

        // New scope, stack workaround.
        {
            bytes[][] memory fidKeys = new bytes[][](2);
            fidKeys[0] = new bytes[](1);
            fidKeys[0][0] = key;

            bytes memory key2 = svm.createBytes(32, "key2");
            fidKeys[1] = new bytes[](1);
            fidKeys[1][0] = key2;

            uint256 fid2 = svm.createUint256("fid2");

            IKeyRegistry.BulkAddKey[] memory keyData1 = new IKeyRegistry.BulkAddKey[](1);
            IKeyRegistry.BulkAddKey[] memory keyData2 = new IKeyRegistry.BulkAddKey[](1);
            keyData1[0] = IKeyRegistry.BulkAddKey({key: key, metadata: ""});
            keyData2[0] = IKeyRegistry.BulkAddKey({key: key2, metadata: ""});

            addData[0] = IKeyRegistry.BulkAddData({fid: fid, keys: keyData1});
            addData[1] = IKeyRegistry.BulkAddData({fid: fid2, keys: keyData2});

            resetData[0] = IKeyRegistry.BulkResetData({fid: fid, keys: fidKeys[0]});
            resetData[1] = IKeyRegistry.BulkResetData({fid: fid2, keys: fidKeys[1]});
        }

        // Generate calldata based on the function selector
        bytes memory args;
        if (selector == keyRegistry.add.selector) {
            // Explicitly branching based on conditions.
            // Note: The negations of conditions are also taken into account.
            split_cases(keyType == uint32(1) && metadataType == uint8(1));
            args = abi.encode(user, keyType, key, metadataType, metadata);
        } else if (selector == keyRegistry.remove.selector) {
            args = abi.encode(key);
        } else if (selector == keyRegistry.removeFor.selector) {
            args = abi.encode(user, key, deadline, sig);
        } else if (selector == keyRegistry.bulkAddKeysForMigration.selector) {
            args = abi.encode(addData);
        } else if (selector == keyRegistry.bulkResetKeysForMigration.selector) {
            args = abi.encode(resetData);
        } else {
            // For functions where all parameters are static (not dynamic arrays or bytes),
            // a raw byte array is sufficient instead of explicitly specifying each argument.
            args = svm.createBytes(1024, "data"); // choose a size that is large enough to cover all parameters
        }
        return abi.encodePacked(selector, args);
    }
}
