// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {ISnapchainConfigRegistry} from "../../src/interfaces/ISnapchainConfigRegistry.sol";
import {SnapchainConfigRegistryTestSuite} from "./SnapchainConfigRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract SnapchainConfigRegistryTest is SnapchainConfigRegistryTestSuite {
    event AppendValidatorSet(
        uint256 indexed index,
        uint64 indexed effectiveAt,
        uint32[] shardIds,
        bytes32[] validatorPublicKeys,
        uint256 configVersion
    );
    event AmendValidatorSet(
        uint256 indexed index,
        uint64 indexed effectiveAt,
        uint32[] shardIds,
        bytes32[] validatorPublicKeys,
        uint256 configVersion
    );
    event RemoveValidatorSet(uint256 indexed index, uint256 configVersion);
    event SetBootstrapPeers(string oldPeers, string newPeers, uint256 configVersion);
    event SetDirectPeers(string oldPeers, string newPeers, uint256 configVersion);

    /**
     * @dev eth_call has no protocol-level gas limit; every limit is node or provider policy. The
     *      geth-family default (`--rpc.gascap`) is 50M, and providers layer their own, usually
     *      lower and often expressed as a timeout rather than a gas number. 10M is a deliberately
     *      conservative floor to hold the renderer to, not a documented universal minimum.
     */
    uint256 internal constant CONSERVATIVE_ETH_CALL_GAS_CAP = 10_000_000;

    /// @dev ~47 validator rotations beyond mainnet's current 10 entries.
    uint256 internal constant PROJECTED_ENTRIES = 150;

    /// @dev Past the point where the full render clears the conservative cap (~195 entries).
    uint256 internal constant BEYOND_LIMIT_ENTRIES = 300;

    uint256 internal constant PAGE_SIZE = 50;

    /*//////////////////////////////////////////////////////////////
                            STORAGE CORRECTNESS
    //////////////////////////////////////////////////////////////*/

    function testFuzzAppendStoresExactly(uint8 keyCount, uint64 effectiveAt) public {
        uint256 n = bound(keyCount, 1, registry.MAX_VALIDATOR_PUBLIC_KEYS());
        bytes32[] memory keys = _distinctKeys(n);

        _append(effectiveAt, _shards(0, 1, 2), keys);

        ISnapchainConfigRegistry.ValidatorSet memory set = registry.validatorSetAt(0);
        assertEq(registry.validatorSetCount(), 1);
        assertEq(set.effectiveAt, effectiveAt);
        assertEq(set.shardIds.length, 3);
        assertEq(set.validatorPublicKeys.length, n);
        for (uint256 i; i < n; ++i) {
            assertEq(set.validatorPublicKeys[i], keys[i]);
        }
    }

    /**
     * @dev The test that catches a botched nested-array copy. Shrinking an amend must resize the
     *      stored arrays, not leave the tail of the previous value behind.
     */
    function testFuzzAmendShrinksArrays(uint8 from, uint8 to) public {
        uint256 n = bound(from, 2, registry.MAX_VALIDATOR_PUBLIC_KEYS());
        uint256 m = bound(to, 1, n - 1);

        _append(0, _shards(0, 1, 2), _distinctKeys(n));
        _amend(0, _shards(0), _distinctKeys(m, 1));

        ISnapchainConfigRegistry.ValidatorSet memory set = registry.validatorSetAt(0);
        assertEq(set.validatorPublicKeys.length, m);
        assertEq(set.shardIds.length, 1);
        assertEq(_count(registry.configToml(), "\",\n"), m);
    }

    function testFuzzAmendGrowsArrays(uint8 from, uint8 to) public {
        uint256 n = bound(from, 1, registry.MAX_VALIDATOR_PUBLIC_KEYS() - 1);
        uint256 m = bound(to, n + 1, registry.MAX_VALIDATOR_PUBLIC_KEYS());

        _append(0, _shards(0), _distinctKeys(n));
        _amend(0, _shards(0, 1, 2), _distinctKeys(m, 1));

        ISnapchainConfigRegistry.ValidatorSet memory set = registry.validatorSetAt(0);
        assertEq(set.validatorPublicKeys.length, m);
        assertEq(set.shardIds.length, 3);
        assertEq(_count(registry.configToml(), "\",\n"), m);
    }

    function testFuzzAmendLeavesEarlierEntriesUntouched(
        uint64 effectiveAt
    ) public {
        uint256 firstEffectiveAt = bound(effectiveAt, 0, type(uint64).max - 1);
        bytes32[] memory first = _distinctKeys(5);

        _append(uint64(firstEffectiveAt), _shards(0, 1, 2), first);
        _append(type(uint64).max, _shards(1), _distinctKeys(3, 1));
        _amend(type(uint64).max, _shards(2), _distinctKeys(7, 2));

        ISnapchainConfigRegistry.ValidatorSet memory set = registry.validatorSetAt(0);
        assertEq(registry.validatorSetCount(), 2);
        assertEq(set.effectiveAt, firstEffectiveAt);
        assertEq(set.validatorPublicKeys.length, 5);
        for (uint256 i; i < 5; ++i) {
            assertEq(set.validatorPublicKeys[i], first[i]);
        }
    }

    /**
     * @dev Regression test for the explicit clear before pop(). Without it, a later push() would
     *      inherit the removed entry's contents and silently resurrect a removed validator.
     */
    function testRemoveThenAppendDoesNotLeakStaleKeys() public {
        bytes32[] memory seven = _distinctKeys(7);
        bytes32[] memory two = _distinctKeys(2, 1);

        _append(0, _shards(0, 1, 2), seven);
        vm.prank(owner);
        registry.removeLatestValidatorSet();
        _append(0, _shards(0), two);

        ISnapchainConfigRegistry.ValidatorSet memory set = registry.validatorSetAt(0);
        assertEq(registry.validatorSetCount(), 1);
        assertEq(set.validatorPublicKeys.length, 2);
        assertEq(set.shardIds.length, 1);
        assertEq(set.validatorPublicKeys[0], two[0]);
        assertEq(set.validatorPublicKeys[1], two[1]);
        assertEq(_count(registry.configToml(), "\",\n"), 2);
    }

    function testAmendWithNoValidatorSets() public {
        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.NoValidatorSets.selector);
        registry.amendLatestValidatorSet(0, _shards(0), _distinctKeys(1));
    }

    function testRemoveWithNoValidatorSets() public {
        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.NoValidatorSets.selector);
        registry.removeLatestValidatorSet();
    }

    /*//////////////////////////////////////////////////////////////
                              EFFECTIVE AT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Must succeed. Within a shard the bound is `>=`, not `>`: a rollout may legitimately land
     *      at a height already used by a sibling entry.
     */
    function testFuzzAppendEqualEffectiveAtSameShard(
        uint64 effectiveAt
    ) public {
        _append(effectiveAt, _shards(0), _distinctKeys(3));
        _append(effectiveAt, _shards(0), _distinctKeys(3, 1));

        assertEq(registry.validatorSetCount(), 2);
        assertEq(registry.validatorSetAt(1).effectiveAt, effectiveAt);
    }

    function testFuzzAppendNonMonotonicSameShard(uint64 first, uint64 second) public {
        uint64 high = uint64(bound(first, 1, type(uint64).max));
        uint64 low = uint64(bound(second, 0, high - 1));

        _append(high, _shards(0), _distinctKeys(3));

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidEffectiveAt.selector);
        registry.appendValidatorSet(low, _shards(0), _distinctKeys(3, 1));
    }

    /**
     * @dev Must succeed. `effectiveAt` is a per-shard counter, so an entry over one shard says
     *      nothing about a later entry over a different one. Shard 0 running far ahead of a message
     *      shard is the normal steady state, and a rollout to that message shard has to stay
     *      expressible at its own height rather than shard 0's.
     */
    function testFuzzAppendNonMonotonicDisjointShards(uint64 first, uint64 second) public {
        uint64 high = uint64(bound(first, 1, type(uint64).max));
        uint64 low = uint64(bound(second, 0, high - 1));

        _append(high, _shards(0), _distinctKeys(3));
        _append(low, _shards(1), _distinctKeys(3, 1));

        assertEq(registry.validatorSetCount(), 2);
        assertEq(registry.validatorSetAt(1).effectiveAt, low);
    }

    /// @dev A single shard in common is enough to bind two entries together.
    function testFuzzAppendNonMonotonicOverlappingShards(uint64 first, uint64 second) public {
        uint64 high = uint64(bound(first, 1, type(uint64).max));
        uint64 low = uint64(bound(second, 0, high - 1));

        _append(high, _shards(0, 1), _distinctKeys(3));

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidEffectiveAt.selector);
        registry.appendValidatorSet(low, _shards(1, 2), _distinctKeys(3, 1));
    }

    /// @dev The bound comes from the most recent entry governing the shard, not from the array tip,
    ///      so intervening entries over other shards do not hide it.
    function testFuzzAppendBoundedByMostRecentSameShardEntry(uint64 first, uint64 second) public {
        uint64 high = uint64(bound(first, 1, type(uint64).max));
        uint64 low = uint64(bound(second, 0, high - 1));

        _append(high, _shards(0), _distinctKeys(3));
        _append(low, _shards(1), _distinctKeys(3, 1));
        _append(low, _shards(2), _distinctKeys(3, 2));

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidEffectiveAt.selector);
        registry.appendValidatorSet(low, _shards(0), _distinctKeys(3, 3));
    }

    function testFuzzAmendNonMonotonicSameShard(uint64 first, uint64 second) public {
        uint64 high = uint64(bound(first, 1, type(uint64).max));
        uint64 low = uint64(bound(second, 0, high - 1));

        _append(high, _shards(0), _distinctKeys(3));
        _append(high, _shards(0), _distinctKeys(3, 1));

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidEffectiveAt.selector);
        registry.amendLatestValidatorSet(low, _shards(0), _distinctKeys(3, 1));
    }

    /// @dev Retargeting the tip at a shard no preceding entry governs frees it from their heights.
    function testFuzzAmendDisjointShardIgnoresPrecedingHeight(uint64 first, uint64 second) public {
        uint64 high = uint64(bound(first, 1, type(uint64).max));
        uint64 low = uint64(bound(second, 0, high - 1));

        _append(high, _shards(0), _distinctKeys(3));
        _append(high, _shards(0), _distinctKeys(3, 1));
        _amend(low, _shards(1), _distinctKeys(3, 2));

        assertEq(registry.validatorSetAt(1).effectiveAt, low);
        assertEq(registry.validatorSetAt(1).shardIds[0], 1);
    }

    /// @dev Amending the only entry has no predecessor to be bounded by.
    function testFuzzAmendFirstEntryIgnoresMonotonicity(uint64 first, uint64 second) public {
        _append(first, _shards(0), _distinctKeys(3));
        _amend(second, _shards(0), _distinctKeys(3, 1));

        assertEq(registry.validatorSetAt(0).effectiveAt, second);
    }

    /**
     * @dev Removing an entry must take its height out of the bound with it. The registry tracks the
     *      running maximum per shard rather than a history, so this only holds because each entry
     *      snapshots what it displaced.
     */
    function testFuzzRemoveRestoresEffectiveAtBound(uint64 first, uint64 second) public {
        uint64 low = uint64(bound(first, 0, type(uint64).max - 1));
        uint64 high = uint64(bound(second, uint256(low) + 1, type(uint64).max));

        _append(low, _shards(0), _distinctKeys(3));
        _append(high, _shards(0), _distinctKeys(3, 1));

        vm.prank(owner);
        registry.removeLatestValidatorSet();

        _append(low, _shards(0), _distinctKeys(3, 2));

        assertEq(registry.validatorSetCount(), 2);
        assertEq(registry.validatorSetAt(1).effectiveAt, low);
    }

    /// @dev Each removal exposes a new tip whose own displaced value must still be known.
    function testRepeatedRemovesRestoreEffectiveAtBound() public {
        _append(10, _shards(0), _distinctKeys(3));
        _append(20, _shards(0), _distinctKeys(3, 1));
        _append(30, _shards(0), _distinctKeys(3, 2));

        vm.startPrank(owner);
        registry.removeLatestValidatorSet();
        registry.removeLatestValidatorSet();
        vm.stopPrank();

        // One entry left, at 10: the bound is back where it started rather than stuck at 20 or 30.
        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidEffectiveAt.selector);
        registry.appendValidatorSet(9, _shards(0), _distinctKeys(3, 3));

        _append(10, _shards(0), _distinctKeys(3, 4));
        assertEq(registry.validatorSetCount(), 2);
    }

    /// @dev Each amend is bounded by the entries before the tip, not by the value it replaces, so
    ///      the tip can be walked back down as well as up.
    function testRepeatedAmendsRestoreEffectiveAtBound() public {
        _append(10, _shards(0), _distinctKeys(3));
        _append(30, _shards(0), _distinctKeys(3, 1));

        _amend(25, _shards(0), _distinctKeys(3, 2));
        _amend(15, _shards(0), _distinctKeys(3, 3));
        _amend(10, _shards(0), _distinctKeys(3, 4));

        assertEq(registry.validatorSetAt(1).effectiveAt, 10);

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidEffectiveAt.selector);
        registry.amendLatestValidatorSet(9, _shards(0), _distinctKeys(3, 5));
    }

    /// @dev An amend that retargets the tip onto different shards must undo its contribution to the
    ///      shards it used to govern, or removing it later would leave those shards bounded by an
    ///      entry that no longer exists.
    function testRemoveAfterAmendChangingShardsRestoresBothBounds() public {
        _append(10, _shards(0), _distinctKeys(3));
        _append(20, _shards(1), _distinctKeys(3, 1));
        _amend(20, _shards(0), _distinctKeys(3, 2));

        vm.prank(owner);
        registry.removeLatestValidatorSet();

        // Shard 1 is governed by no surviving entry, and shard 0 is back to entry 0's height.
        _append(0, _shards(1), _distinctKeys(3, 3));
        _append(10, _shards(0), _distinctKeys(3, 4));

        assertEq(registry.validatorSetCount(), 3);
    }

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    function testAppendEmptyShardIds() public {
        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidShardIds.selector);
        registry.appendValidatorSet(0, new uint32[](0), _distinctKeys(3));
    }

    function testAppendTooManyShardIds() public {
        uint256 max = registry.MAX_SHARD_IDS();
        uint32[] memory shardIds = new uint32[](max + 1);
        for (uint256 i; i < max + 1; ++i) {
            shardIds[i] = uint32(i);
        }

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidShardIds.selector);
        registry.appendValidatorSet(0, shardIds, _distinctKeys(3));
    }

    function testFuzzAppendDuplicateShardId(
        uint32 shardId
    ) public {
        uint32[] memory shardIds = new uint32[](2);
        shardIds[0] = shardId;
        shardIds[1] = shardId;

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidShardIds.selector);
        registry.appendValidatorSet(0, shardIds, _distinctKeys(3));
    }

    function testAppendEmptyValidatorPublicKeys() public {
        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidValidatorPublicKeys.selector);
        registry.appendValidatorSet(0, _shards(0), new bytes32[](0));
    }

    function testAppendTooManyValidatorPublicKeys() public {
        bytes32[] memory keys = _distinctKeys(registry.MAX_VALIDATOR_PUBLIC_KEYS() + 1);

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidValidatorPublicKeys.selector);
        registry.appendValidatorSet(0, _shards(0), keys);
    }

    function testFuzzAppendZeroValidatorPublicKey(
        uint8 position
    ) public {
        bytes32[] memory keys = _distinctKeys(5);
        keys[bound(position, 0, 4)] = bytes32(0);

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidValidatorPublicKeys.selector);
        registry.appendValidatorSet(0, _shards(0), keys);
    }

    /// @dev A duplicate key silently doubles that operator's voting weight, so this is a safety
    ///      property rather than hygiene.
    function testFuzzAppendDuplicateValidatorPublicKey(
        uint8 position
    ) public {
        bytes32[] memory keys = _distinctKeys(5);
        keys[bound(position, 1, 4)] = keys[0];

        vm.prank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidValidatorPublicKeys.selector);
        registry.appendValidatorSet(0, _shards(0), keys);
    }

    function testFuzzValidatorSetAtOutOfRange(
        uint256 index
    ) public {
        _append(0, _shards(0), _distinctKeys(3));

        vm.expectRevert(ISnapchainConfigRegistry.InvalidRange.selector);
        registry.validatorSetAt(bound(index, 1, type(uint256).max));
    }

    /*//////////////////////////////////////////////////////////////
                              PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanAppend(
        address caller
    ) public {
        _assumeClean(caller);
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.appendValidatorSet(0, _shards(0), _distinctKeys(3));
    }

    function testFuzzOnlyOwnerCanAmend(
        address caller
    ) public {
        _assumeClean(caller);
        vm.assume(caller != owner);
        _append(0, _shards(0), _distinctKeys(3));

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.amendLatestValidatorSet(0, _shards(0), _distinctKeys(3, 1));
    }

    function testFuzzOnlyOwnerCanRemove(
        address caller
    ) public {
        _assumeClean(caller);
        vm.assume(caller != owner);
        _append(0, _shards(0), _distinctKeys(3));

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.removeLatestValidatorSet();
    }

    function testFuzzOnlyOwnerCanSetPeers(
        address caller
    ) public {
        _assumeClean(caller);
        vm.assume(caller != owner);

        vm.startPrank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setBootstrapPeers("a");
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setDirectPeers("a");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            TOML INJECTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Cross-check the contract's allowlist bitmap against an independently written predicate,
     *      one byte at a time. The bitmap is two opaque hex constants; this is what makes them safe
     *      to merge.
     */
    function testPeerCharAllowlist() public {
        for (uint256 c; c < 256; ++c) {
            string memory input = _oneChar(uint8(c));

            vm.prank(owner);
            if (_expectedAllowed(uint8(c))) {
                registry.setBootstrapPeers(input);
                assertEq(registry.bootstrapPeers(), input);
            } else {
                vm.expectRevert(ISnapchainConfigRegistry.InvalidPeerString.selector);
                registry.setBootstrapPeers(input);
            }
        }
    }

    /// @dev Written from the spec, deliberately not from the contract's bitmap.
    function _expectedAllowed(
        uint8 char
    ) internal pure returns (bool) {
        if (char >= 0x61 && char <= 0x7A) return true; // a-z
        if (char >= 0x41 && char <= 0x5A) return true; // A-Z
        if (char >= 0x30 && char <= 0x39) return true; // 0-9
        return char == 0x20 // space
            || char == 0x2C // ,
            || char == 0x2D // -
            || char == 0x2E // .
            || char == 0x2F // /
            || char == 0x3A // :
            || char == 0x5F; // _
    }

    function testInjectionQuote() public {
        _expectPeerStringRejected("/ip4/1.2.3.4/udp/3382/quic-v1\"");
    }

    function testInjectionNewline() public {
        _expectPeerStringRejected("/ip4/1.2.3.4/udp/3382/quic-v1\n");
    }

    function testInjectionBackslash() public {
        _expectPeerStringRejected("/ip4/1.2.3.4/udp/3382/quic-v1\\");
    }

    /// @dev The payload this whole allowlist exists to stop: close the literal, then append a
    ///      validator set at genesis naming an attacker's key.
    function testInjectionValidatorSetTable() public {
        _expectPeerStringRejected(
            "\"\n\n[[consensus.validator_sets]]\neffective_at = 0\nshard_ids = [0]\n"
            "validator_public_keys = [\n  \"deadbeef\",\n]\n"
        );
    }

    function testInjectionTooLong() public {
        bytes memory long = new bytes(registry.MAX_PEER_STRING_LENGTH() + 1);
        for (uint256 i; i < long.length; ++i) {
            long[i] = "a";
        }
        _expectPeerStringRejected(string(long));
    }

    function _expectPeerStringRejected(
        string memory peers
    ) internal {
        vm.startPrank(owner);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidPeerString.selector);
        registry.setBootstrapPeers(peers);
        vm.expectRevert(ISnapchainConfigRegistry.InvalidPeerString.selector);
        registry.setDirectPeers(peers);
        vm.stopPrank();
    }

    function testEmptyPeerStringsAreValid() public {
        vm.startPrank(owner);
        registry.setBootstrapPeers("");
        registry.setDirectPeers("");
        vm.stopPrank();

        assertEq(registry.peersToml(), "[gossip]\nbootstrap_peers = \"\"\ndirect_peers = \"\"\n");
    }

    /**
     * @dev The invariant behind the enumerated injection tests. With keys as bytes32 and peers
     *      behind the allowlist, no field can contain a quote, so the count is exact: two per key
     *      line plus four for the two peer values.
     */
    function testFuzzConfigTomlHasBalancedQuotes(uint8 setCount, uint8 keyCount) public {
        uint256 sets = bound(setCount, 1, 8);
        uint256 keys = bound(keyCount, 1, 8);

        for (uint256 i; i < sets; ++i) {
            _append(0, _shards(0, 1, 2), _distinctKeys(keys, i));
        }
        vm.startPrank(owner);
        registry.setBootstrapPeers(MAINNET_BOOTSTRAP_PEERS);
        registry.setDirectPeers(MAINNET_DIRECT_PEERS);
        vm.stopPrank();

        assertEq(_count(registry.configToml(), "\""), 2 * sets * keys + 4);
    }

    /*//////////////////////////////////////////////////////////////
                               RENDERING
    //////////////////////////////////////////////////////////////*/

    /// @dev Differential against forge's own hex formatting, with the 0x prefix stripped.
    function testFuzzRendersKeyAsUnprefixedLowercaseHex(
        bytes32 key
    ) public {
        vm.assume(key != bytes32(0));
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = key;

        _append(0, _shards(0), keys);

        bytes memory full = bytes(vm.toString(key));
        bytes memory stripped = new bytes(64);
        for (uint256 i; i < 64; ++i) {
            stripped[i] = full[i + 2];
        }
        assertEq(_count(registry.configToml(), string(abi.encodePacked("  \"", stripped, "\",\n"))), 1);
    }

    function testFuzzRendersEffectiveAtAsPlainDecimal(
        uint64 effectiveAt
    ) public {
        _append(effectiveAt, _shards(0), _distinctKeys(1));

        string memory expected = string(abi.encodePacked("effective_at = ", vm.toString(uint256(effectiveAt)), "\n"));
        assertEq(_count(registry.configToml(), expected), 1);
    }

    function testFuzzRendersShardIdsWithoutTrailingComma(uint32 a, uint32 b, uint32 c) public {
        vm.assume(a != b && b != c && a != c);
        _append(0, _shards(a, b, c), _distinctKeys(1));

        string memory expected = string(
            abi.encodePacked(
                "shard_ids = [",
                vm.toString(uint256(a)),
                ", ",
                vm.toString(uint256(b)),
                ", ",
                vm.toString(uint256(c)),
                "]\n"
            )
        );
        assertEq(_count(registry.configToml(), expected), 1);
    }

    function testConfigTomlWithNoValidatorSets() public view {
        assertEq(registry.configToml(), "[gossip]\nbootstrap_peers = \"\"\ndirect_peers = \"\"\n");
    }

    /*//////////////////////////////////////////////////////////////
                               PAGINATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzPaginationComposes(uint8 setCount, uint8 splitAt) public {
        uint256 n = bound(setCount, 0, 12);
        uint256 split = bound(splitAt, 0, n);

        for (uint256 i; i < n; ++i) {
            _append(0, _shards(0, 1, 2), _distinctKeys(3, i));
        }

        string memory whole = registry.validatorSetsToml(0, n);
        string memory joined =
            string(abi.encodePacked(registry.validatorSetsToml(0, split), registry.validatorSetsToml(split, n)));
        assertEq(joined, whole);
    }

    function testFuzzConfigTomlEqualsRangePlusPeers(
        uint8 setCount
    ) public {
        uint256 n = bound(setCount, 0, 12);
        for (uint256 i; i < n; ++i) {
            _append(0, _shards(0), _distinctKeys(3, i));
        }
        vm.prank(owner);
        registry.setBootstrapPeers(MAINNET_BOOTSTRAP_PEERS);

        string memory expected =
            string(abi.encodePacked(registry.validatorSetsToml(0, registry.validatorSetCount()), registry.peersToml()));
        assertEq(registry.configToml(), expected);
    }

    function testFuzzValidatorSetsTomlInvalidRange(uint8 start, uint8 end) public {
        _append(0, _shards(0), _distinctKeys(3));

        uint256 lo = bound(start, 2, 100);
        uint256 hi = bound(end, 0, 1);

        vm.expectRevert(ISnapchainConfigRegistry.InvalidRange.selector);
        registry.validatorSetsToml(lo, hi);

        vm.expectRevert(ISnapchainConfigRegistry.InvalidRange.selector);
        registry.validatorSetsToml(0, lo);
    }

    /*//////////////////////////////////////////////////////////////
                             CONFIG VERSION
    //////////////////////////////////////////////////////////////*/

    function testFuzzConfigVersionMonotonic(
        uint8 steps
    ) public {
        uint256 n = bound(steps, 1, 20);
        assertEq(registry.configVersion(), 0);

        for (uint256 i; i < n; ++i) {
            _append(0, _shards(0), _distinctKeys(3, i));
            assertEq(registry.configVersion(), i + 1);
        }

        uint256 afterAppends = registry.configVersion();

        vm.startPrank(owner);
        registry.setBootstrapPeers("a");
        assertEq(registry.configVersion(), afterAppends + 1);
        registry.setDirectPeers("b");
        assertEq(registry.configVersion(), afterAppends + 2);
        registry.amendLatestValidatorSet(0, _shards(1), _distinctKeys(2, 99));
        assertEq(registry.configVersion(), afterAppends + 3);
        registry.removeLatestValidatorSet();
        assertEq(registry.configVersion(), afterAppends + 4);
        vm.stopPrank();

        // View calls never move it.
        registry.configToml();
        registry.validatorSets();
        assertEq(registry.configVersion(), afterAppends + 4);
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    function testEmitAppendValidatorSet() public {
        uint32[] memory shardIds = _shards(0, 1, 2);
        bytes32[] memory keys = _distinctKeys(3);

        vm.expectEmit(true, true, false, true);
        emit AppendValidatorSet(0, 42, shardIds, keys, 1);

        vm.prank(owner);
        registry.appendValidatorSet(42, shardIds, keys);
    }

    function testEmitAmendValidatorSet() public {
        uint32[] memory shardIds = _shards(1);
        bytes32[] memory keys = _distinctKeys(3, 1);
        _append(42, _shards(0), _distinctKeys(3));

        vm.expectEmit(true, true, false, true);
        emit AmendValidatorSet(0, 43, shardIds, keys, 2);

        vm.prank(owner);
        registry.amendLatestValidatorSet(43, shardIds, keys);
    }

    function testEmitRemoveValidatorSet() public {
        _append(42, _shards(0), _distinctKeys(3));

        vm.expectEmit(true, false, false, true);
        emit RemoveValidatorSet(0, 2);

        vm.prank(owner);
        registry.removeLatestValidatorSet();
    }

    function testEmitSetPeers() public {
        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true);
        emit SetBootstrapPeers("", "a", 1);
        registry.setBootstrapPeers("a");

        vm.expectEmit(false, false, false, true);
        emit SetBootstrapPeers("a", "b", 2);
        registry.setBootstrapPeers("b");

        vm.expectEmit(false, false, false, true);
        emit SetDirectPeers("", "c", 3);
        registry.setDirectPeers("c");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              GOLDEN OUTPUT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Snapchain mainnet's validator_sets and gossip peers as this contract renders them.
     *
     *      Deliberately not byte-identical to validators.toml. That file carries comments, writes
     *      integers with underscore separators (26_386_684) and spaces its arrays inside the
     *      brackets ([ 0, 1, 2 ]); the contract emits 26386684 and [0, 1, 2]. A TOML parser cannot
     *      tell the two apart. This constant is the normalized form -- do not "fix" the difference.
     *
     *      Each rendered line is its own adjacent string literal. forge fmt packs the short ones
     *      several to a source line; the key lines are too long to pack and stay one per line.
     */
    string internal constant GOLDEN_MAINNET_CONFIG_TOML = "[[consensus.validator_sets]]\n" "effective_at = 0\n"
        "shard_ids = [0, 1, 2]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"2c0f58a364b7959c85e49b5a50d14d220c16f8bd7879b0d5d3f68b32de83ecb8\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 26386684\n" "shard_ids = [0]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 26556206\n" "shard_ids = [2]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 26701296\n" "shard_ids = [1]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 28415000\n" "shard_ids = [0]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n"
        "  \"80d7800b45db3ec6d6e4be4d278db1aea1c7a77206941ec976a8680ecbe56860\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 28706000\n" "shard_ids = [2]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n"
        "  \"80d7800b45db3ec6d6e4be4d278db1aea1c7a77206941ec976a8680ecbe56860\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 28852000\n" "shard_ids = [1]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n"
        "  \"80d7800b45db3ec6d6e4be4d278db1aea1c7a77206941ec976a8680ecbe56860\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 39180000\n" "shard_ids = [0]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n"
        "  \"80d7800b45db3ec6d6e4be4d278db1aea1c7a77206941ec976a8680ecbe56860\",\n"
        "  \"3376e30a4d8e7ea596f3c066f7e9f3a960fad76ed0b6fb7de66552cbe9318b5e\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 39624000\n" "shard_ids = [2]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n"
        "  \"80d7800b45db3ec6d6e4be4d278db1aea1c7a77206941ec976a8680ecbe56860\",\n"
        "  \"3376e30a4d8e7ea596f3c066f7e9f3a960fad76ed0b6fb7de66552cbe9318b5e\",\n" "]\n" "\n"
        "[[consensus.validator_sets]]\n" "effective_at = 39798000\n" "shard_ids = [1]\n" "validator_public_keys = [\n"
        "  \"29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970\",\n"
        "  \"6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72\",\n"
        "  \"81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8\",\n"
        "  \"db65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081\",\n"
        "  \"67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102\",\n"
        "  \"80d7800b45db3ec6d6e4be4d278db1aea1c7a77206941ec976a8680ecbe56860\",\n"
        "  \"3376e30a4d8e7ea596f3c066f7e9f3a960fad76ed0b6fb7de66552cbe9318b5e\",\n" "]\n" "\n" "[gossip]\n"
        "bootstrap_peers = \"/ip4/10.0.0.148/udp/3382/quic-v1, /ip4/10.0.2.165/udp/3382/quic-v1, /ip4/107.20.169.23"
        "6/udp/3382/quic-v1, /ip4/54.157.62.17/udp/3382/quic-v1, /ip4/34.4.32.36/udp/3382/quic-v1, /ip4/108.132.114"
        ".186/udp/3382/quic-v1, /ip4/100.30.67.21/udp/3382/quic-v1\"\n"
        "direct_peers = \"12D3KooWGmXDC2SfjSG7h7DchyVJHMB4GpA8JYpHf9iwz8L8BFqB, 12D3KooWJVyaQRovV1rjV8TzkN3cRiysACy"
        "ey86kXDLdvf6JRq5Z, 12D3KooWCc28TYrrXFivwUshyZ8R5HqPMgx4f7AP54iCDLYr7kFR, 12D3KooWQaoBw2gvdmfGdXjepEQU9i47F"
        "XxvsCZ6wu8Vn4gwvHm2, 12D3KooWJVJwgRAitzcdSFmjK8AVVyzFMc5BVKTuUJk2j71nTAMu, 12D3KooWDHG75L7M8t45d6moKhnhLHg"
        "M9BYt1PBTgZfYEgsXXUa9\"\n";

    function testGoldenMainnetConfigToml() public {
        _seedMainnet();
        assertEq(registry.configToml(), GOLDEN_MAINNET_CONFIG_TOML);
    }

    function testGoldenMainnetStructure() public {
        _seedMainnet();

        assertEq(registry.validatorSetCount(), 10);
        assertEq(registry.validatorSetAt(0).effectiveAt, 0);
        assertEq(registry.validatorSetAt(0).shardIds.length, 3);
        assertEq(registry.validatorSetAt(9).effectiveAt, 39_798_000);
        assertEq(_count(registry.configToml(), "[[consensus.validator_sets]]\n"), 10);
        assertEq(_count(registry.configToml(), "\",\n"), 59);
    }

    /*//////////////////////////////////////////////////////////////
                                GAS GUARD
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev `configToml()` at a scale the network will plausibly reach, in the shape it will
     *      actually reach it: many entries of ~8 keys, not a few entries of many keys.
     *
     *      Mainnet holds 10 entries today and grows by one per shard per rotation, so 3 per
     *      rotation across the current 3 shards. 150 entries is roughly 47 rotations beyond
     *      today; the history to date is 3 rotations in about 15 months.
     *
     *      Without this, a refactor to a flat one-concat-per-line loop passes every correctness
     *      test here and quietly makes the canonical getter uncallable on a public RPC.
     */
    function testGasConfigTomlAtProjectedScale() public {
        _seedEntries(PROJECTED_ENTRIES, 8);

        uint256 before = gasleft();
        string memory toml = registry.configToml();
        uint256 used = before - gasleft();

        emit log_named_uint("entries", PROJECTED_ENTRIES);
        emit log_named_uint("configToml bytes", bytes(toml).length);
        emit log_named_uint("configToml gas", used);
        assertLt(used, CONSERVATIVE_ETH_CALL_GAS_CAP);
    }

    /**
     * @dev The test that makes the ceiling and its mitigation plain at the same time.
     *
     *      `configToml()` is superlinear in entry count and does eventually stop fitting inside a
     *      conservative eth_call budget -- measured, it crosses 10M at roughly 195 entries and 18M
     *      at 300. `validatorSetsToml` is the documented escape hatch, and this asserts it is a
     *      real one rather than decoration: at a scale where the full render is well past the
     *      conservative cap, a fixed 50-entry page still costs about 3M, and the pages reassemble
     *      into byte-identical output.
     *
     *      Deliberately no upper-bound assertion on the full render. Making a test depend on
     *      `configToml()` staying expensive would fail the day someone optimizes it, which is not
     *      a regression worth reporting.
     */
    function testPaginationStaysViableBeyondFullRenderLimit() public {
        _seedEntries(BEYOND_LIMIT_ENTRIES, 8);

        uint256 before = gasleft();
        string memory whole = registry.configToml();
        emit log_named_uint("full render gas", before - gasleft());
        emit log_named_uint("full render bytes", bytes(whole).length);

        bytes memory reassembled;
        uint256 worstPage;
        for (uint256 start; start < BEYOND_LIMIT_ENTRIES; start += PAGE_SIZE) {
            uint256 end = start + PAGE_SIZE > BEYOND_LIMIT_ENTRIES ? BEYOND_LIMIT_ENTRIES : start + PAGE_SIZE;

            uint256 pageBefore = gasleft();
            string memory page = registry.validatorSetsToml(start, end);
            uint256 pageUsed = pageBefore - gasleft();
            if (pageUsed > worstPage) worstPage = pageUsed;

            reassembled = bytes.concat(reassembled, bytes(page));
        }

        emit log_named_uint("worst page gas", worstPage);
        assertLt(worstPage, CONSERVATIVE_ETH_CALL_GAS_CAP / 2);
        assertEq(string(bytes.concat(reassembled, bytes(registry.peersToml()))), whole);
    }

    function _seedEntries(uint256 count, uint256 keysPerEntry) internal {
        uint32[] memory shardIds = _shards(0, 1, 2);
        for (uint256 i; i < count; ++i) {
            _append(0, shardIds, _distinctKeys(keysPerEntry, i));
        }
        vm.startPrank(owner);
        registry.setBootstrapPeers(MAINNET_BOOTSTRAP_PEERS);
        registry.setDirectPeers(MAINNET_DIRECT_PEERS);
        vm.stopPrank();
    }
}
