// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {IdRegistryHarness} from "../Utils.sol";

contract KeyRegistrySymTest is SymTest, Test {
    IdRegistryHarness idRegistry;
    address trustedCaller;

    KeyRegistry keyRegistry;
    uint256 gracePeriod;

    uint256 x;
    bytes xkey;

    function setUp() public {
        // Setup IdRegistry
        idRegistry = new IdRegistryHarness(address(this));

        trustedCaller = address(0x1000);
        idRegistry.setTrustedCaller(trustedCaller);

        // Register fids
        vm.prank(trustedCaller);
        idRegistry.trustedRegister(address(0x1001), address(0x2001));
        vm.prank(trustedCaller);
        idRegistry.trustedRegister(address(0x1002), address(0x2002));
        vm.prank(trustedCaller);
        idRegistry.trustedRegister(address(0x1003), address(0x2003));

        assert(idRegistry.idOf(address(0x1001)) == 1);
        assert(idRegistry.idOf(address(0x1002)) == 2);
        assert(idRegistry.idOf(address(0x1003)) == 3);

        assert(idRegistry.getRecoveryOf(1) == address(0x2001));
        assert(idRegistry.getRecoveryOf(2) == address(0x2002));
        assert(idRegistry.getRecoveryOf(3) == address(0x2003));

        // Setup KeyRegistry
        gracePeriod = svm.createUint(24, "gracePeriod");
        keyRegistry = new KeyRegistry(address(idRegistry), uint24(gracePeriod), address(this));
        assert(keyRegistry.gracePeriod() == gracePeriod);

        // Set initial states:
        // - fid 1: removed
        // - fid 2: added
        // - fid 3: null

        bytes memory key1 = svm.createBytes(32, "key1");
        vm.prank(address(0x1001));
        keyRegistry.add(1, 1, key1, "");
        vm.prank(address(0x1001));
        keyRegistry.remove(1, key1);
        assert(keyRegistry.keyDataOf(1, key1).state == KeyRegistry.KeyState.REMOVED);

        bytes memory key2 = svm.createBytes(32, "key2");
        vm.prank(address(0x1002));
        keyRegistry.add(2, 1, key2, "");
        assert(keyRegistry.keyDataOf(2, key2).state == KeyRegistry.KeyState.ADDED);

        // Create symbolic fid and key
        x = svm.createUint256("x");
        xkey = svm.createBytes(32, "xkey");
    }

    // Verify the KeyRegistry invariants
    function check_invariant(bytes4 selector, address caller) public {
        // Additional setup to cover various input states
        if (svm.createBool("migrateKeys?")) {
            keyRegistry.migrateKeys();
        }
        if (svm.createBool("disableTrustedOnly?")) {
            idRegistry.disableTrustedOnly();
        }
        if (svm.createBool("pauseRegistration?")) {
            idRegistry.pauseRegistration();
        }
        vm.warp(svm.createUint(64, "timestamp2"));

        // Record pre-state
        KeyRegistry.KeyState oldStateX = keyRegistry.keyDataOf(x, xkey).state;

        uint256 oldCallerId = idRegistry.idOf(caller);

        bool isNotMigratedOrGracePeriod =
            !keyRegistry.isMigrated() || block.timestamp <= keyRegistry.keysMigratedAt() + gracePeriod;

        // Execute an arbitrary tx to KeyRegistry
        vm.prank(caller);
        (bool success,) = address(keyRegistry).call(mk_calldata(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        KeyRegistry.KeyState newStateX = keyRegistry.keyDataOf(x, xkey).state;

        // Verify invariant properties

        if (newStateX != oldStateX) {
            // If the state of fid x is changed by any transaction to KeyRegistry,
            // ensure that the state transition satisfies the following properties.

            // Ensure that the REMOVED state does not allow any state transitions.
            assert(oldStateX != KeyRegistry.KeyState.REMOVED);

            if (newStateX == KeyRegistry.KeyState.REMOVED) {
                // For a transition to REMOVED, ensure that:
                // - The previous state must be ADD.
                // - The transition can only be made by remove(), where:
                //   - It must be called by the owner of fid x.
                assert(oldStateX == KeyRegistry.KeyState.ADDED);
                assert(selector == keyRegistry.remove.selector);
                assert(oldCallerId == x);
            } else if (newStateX == KeyRegistry.KeyState.ADDED) {
                // For a transition to ADDED, ensure that:
                // - The previous state must be NULL.
                // - The transition can only be made by either add() or bulkAdd(), where:
                //   - add() must be called by the owner of fid x.
                //   - bulkAdd() must be called by the owner of KeyRegistry.
                //   - bulkAdd() must be called before the key migration or within the grade period following the migration.
                assert(oldStateX == KeyRegistry.KeyState.NULL);
                if (selector == keyRegistry.add.selector) {
                    assert(oldCallerId == x);
                } else {
                    assert(selector == keyRegistry.bulkAddKeysForMigration.selector);
                    assert(caller == address(this)); // `this` is the owner of KeyRegistry
                    assert(isNotMigratedOrGracePeriod);
                }
            } else if (newStateX == KeyRegistry.KeyState.NULL) {
                // For a transition to NULL, ensure that:
                // - The previous state must be ADDED.
                // - The transition can only be made by bulkReset(), where:
                //   - It must be called by the owner of KeyRegistry.
                //   - It must be called before the key migration or within the grade period following the migration.
                assert(oldStateX == KeyRegistry.KeyState.ADDED);
                assert(selector == keyRegistry.bulkResetKeysForMigration.selector);
                assert(caller == address(this)); // `this` is the owner of KeyRegistry
                assert(isNotMigratedOrGracePeriod);
            } else {
                // Ensure that no other state transitions are possible.
                assert(false);
            }
        }
    }

    function mk_calldata(bytes4 selector) internal returns (bytes memory args) {
        // Ignore view functions
        vm.assume(selector != keyRegistry.keyDataOf.selector);
        vm.assume(selector != keyRegistry.keys.selector);

        // Create symbolic values to be included in calldata
        uint256 fid = svm.createUint256("fid");
        uint32 scheme = uint32(svm.createUint(32, "scheme"));
        bytes memory key = svm.createBytes(32, "key");
        bytes memory metadata = svm.createBytes(32, "metadata");

        // Halmos requires symbolic dynamic arrays to be given with a specific size.
        // In this test, we provide arrays with length 2.
        uint256[] memory fids = new uint256[](2);
        fids[0] = fid;
        fids[1] = svm.createUint256("fid2");

        bytes[][] memory fidKeys = new bytes[][](2);
        fidKeys[0] = new bytes[](1);
        fidKeys[0][0] = key;
        fidKeys[1] = new bytes[](1);
        fidKeys[1][0] = svm.createBytes(32, "key2");

        // Generate calldata based on the function selector
        bytes memory args;
        if (selector == keyRegistry.add.selector) {
            args = abi.encode(fid, scheme, key, metadata);
        } else if (selector == keyRegistry.remove.selector) {
            args = abi.encode(fid, key);
        } else if (selector == keyRegistry.bulkAddKeysForMigration.selector) {
            args = abi.encode(fids, fidKeys, metadata);
        } else if (selector == keyRegistry.bulkResetKeysForMigration.selector) {
            args = abi.encode(fids, fidKeys);
        } else {
            // For functions where all parameters are static (not dynamic arrays or bytes),
            // a raw byte array is sufficient instead of explicitly specifying each argument.
            args = svm.createBytes(1024, "data"); // choose a size that is large enough to cover all parameters
        }
        return abi.encodePacked(selector, args);
    }
}
