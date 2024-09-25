// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {IKeyRegistry} from "../../src/interfaces/IKeyRegistry.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";
import {KeyRegistryHarness} from "./utils/KeyRegistryHarness.sol";
import {IdRegistry} from "../../src/IdRegistry.sol";
import {StubValidator} from "../Utils.sol";

/// @custom:halmos --default-bytes-lengths 0,32,1024,65
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
    function check_Invariants(address caller) public {
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
        bytes memory data = svm.createCalldata("KeyRegistry");
        bytes4 selector = bytes4(data);

        // Link the first argument of removeFor() to the user variable so that it can be used later in assertions
        if (selector == keyRegistry.removeFor.selector) {
            vm.assume(user == address(uint160(uint256(bytes32(this.slice(data, 4, 36))))));
        }

        vm.prank(caller);
        (bool success,) = address(keyRegistry).call(data);
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

    function slice(bytes calldata data, uint start, uint end) external returns (bytes memory) {
        return data[start:end];
    }
}
