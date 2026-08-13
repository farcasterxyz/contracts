// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISnapchainConfigRegistry} from "../../src/interfaces/ISnapchainConfigRegistry.sol";

/**
 * @title SnapchainConfigRegistrySeed
 *
 * @notice The validator-set history and gossip peer lists a freshly deployed SnapchainConfigRegistry
 *         is seeded with, held in one place so the deploy script and the golden test agree by
 *         construction rather than by two copies staying in sync.
 *
 * @dev Seed data is selected by `block.chainid` rather than passed in as a parameter. A registry
 *      seeded with the wrong network's validator set is not a recoverable mistake: history is
 *      append-only, so the only remedy is to redeploy at a fresh salt and repoint every node. The
 *      chain id is the one input that cannot be fat-fingered at broadcast time.
 */
abstract contract SnapchainConfigRegistrySeed {
    /// @dev Revert rather than deploy an unseeded or wrongly seeded registry on an unknown chain.
    error NoSeedDataForChain(uint256 chainId);

    /*//////////////////////////////////////////////////////////////
                                CHAIN IDS
    //////////////////////////////////////////////////////////////*/

    /// @dev Home of the registry serving the Snapchain **Mainnet** network.
    uint256 internal constant ETH_MAINNET_CHAIN_ID = 1;

    /// @dev Home of the registry serving the Snapchain **Testnet** network.
    uint256 internal constant ETH_SEPOLIA_CHAIN_ID = 11_155_111;

    /*//////////////////////////////////////////////////////////////
                          MAINNET SEED DATA
    //////////////////////////////////////////////////////////////*/

    // The eight distinct validator keys in Snapchain mainnet's validators.toml, numbered as that
    // file numbers them. V4 was replaced by V6 across all shards; V7 and V8 were added later.
    bytes32 internal constant V1 = 0x29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970;
    bytes32 internal constant V2 = 0x6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72;
    bytes32 internal constant V3 = 0x81032ecefa4260e5a63424f5a4b8b18b52d717a52583b3ffe22c4a7b084911b8;
    bytes32 internal constant V4 = 0x2c0f58a364b7959c85e49b5a50d14d220c16f8bd7879b0d5d3f68b32de83ecb8;
    bytes32 internal constant V5 = 0x67474a42e0c6507198b73373b0558dfc94616b976ecfdf5c45fae11e2bee7102;
    bytes32 internal constant V6 = 0xdb65769be751f402fe9ea2fdf21679a870ea0e088454bbc47e02c4cc6c258081;
    bytes32 internal constant V7 = 0x80d7800b45db3ec6d6e4be4d278db1aea1c7a77206941ec976a8680ecbe56860;
    bytes32 internal constant V8 = 0x3376e30a4d8e7ea596f3c066f7e9f3a960fad76ed0b6fb7de66552cbe9318b5e;

    /**
     * @dev Gossip peers as configured on one Snapchain mainnet validator today.
     *
     *      PROVISIONAL. Two things about these values are unresolved and must be settled before a
     *      mainnet broadcast, not after:
     *
     *      1. The first two entries are 10.0.x.x addresses, routable only inside the Neynar VPC.
     *         Publishing them in a registry that external validators read makes the list actively
     *         misleading for everyone outside that network.
     *      2. Every node currently runs its own list, each omitting itself, so there is no single
     *         canonical pair to seed. Whatever goes onchain is by definition a new list rather than
     *         a transcription of an existing one.
     *
     *      Both are open questions on C6. Until they are answered these strings exist to exercise
     *      the renderer and the peer-string allowlist against realistic values.
     */
    string internal constant MAINNET_BOOTSTRAP_PEERS = "/ip4/10.0.0.148/udp/3382/quic-v1,"
        " /ip4/10.0.2.165/udp/3382/quic-v1, /ip4/107.20.169.236/udp/3382/quic-v1,"
        " /ip4/54.157.62.17/udp/3382/quic-v1, /ip4/34.4.32.36/udp/3382/quic-v1,"
        " /ip4/108.132.114.186/udp/3382/quic-v1, /ip4/100.30.67.21/udp/3382/quic-v1";

    string internal constant MAINNET_DIRECT_PEERS = "12D3KooWGmXDC2SfjSG7h7DchyVJHMB4GpA8JYpHf9iwz8L8BFqB,"
        " 12D3KooWJVyaQRovV1rjV8TzkN3cRiysACyey86kXDLdvf6JRq5Z, 12D3KooWCc28TYrrXFivwUshyZ8R5HqPMgx4f7AP54iCDLYr7kFR,"
        " 12D3KooWQaoBw2gvdmfGdXjepEQU9i47FXxvsCZ6wu8Vn4gwvHm2, 12D3KooWJVJwgRAitzcdSFmjK8AVVyzFMc5BVKTuUJk2j71nTAMu,"
        " 12D3KooWDHG75L7M8t45d6moKhnhLHgM9BYt1PBTgZfYEgsXXUa9";

    /*//////////////////////////////////////////////////////////////
                          TESTNET SEED DATA
    //////////////////////////////////////////////////////////////*/

    // The seven distinct validator keys in Snapchain testnet's history, numbered by first
    // appearance in `snapchain-deployer/.stack/deploy.yml`. Node names are from the operator's
    // key-to-host mapping, confirmed against the `signers` field of live commit certificates.
    //
    // T4 and T5 are retired: T4 ran only from genesis to 24_811_937, T5 replaced it and left at
    // 28_681_000. Neither is in the current set, and both are kept because the history is what read
    // nodes verify old commit signatures against.
    bytes32 internal constant T1 = 0xe89dda4bff3ed5f75f56656a661f9f3e972b7206852dee7bfa65c6cee341e7ae; // juno
    bytes32 internal constant T2 = 0x719a2a8331e05a3c5e2f4689fc71e7eabfea96d79c69df773a6fc8d8962dfda4; // iris
    bytes32 internal constant T3 = 0x5b5eb128729aedd86b626f0d60267f770025a551989c422a8f6959ce0bcf24de; // vega
    bytes32 internal constant T4 = 0x9b8e23233565a6d75e545b3750052ca0a19fe71b21bfb91a020498875f426e2e; // retired
    bytes32 internal constant T5 = 0x634d5108d0d260eaa41e1c7e34ed4ec4549b2558ae2e1f8a3cb8e02f725e7501; // retired
    bytes32 internal constant T6 = 0x1694afcc51709e4e2cb94e20bc99f9ea75f5d7ae7eeae66ffc6a350ff1cfd815; // merry
    bytes32 internal constant T7 = 0xd1facefc03296a24d0d0b1c474e72ca2a84a48199c972d6f37d4722de450a056; // gloin

    /**
     * @dev Gossip peers for Snapchain testnet.
     *
     *      Taken from tau, the read node, rather than from a validator. Validators each run a list
     *      that omits themselves, so no validator's list is complete; tau omits nothing, which makes
     *      it the only node whose configured view is the whole cluster. The five bootstrap entries
     *      are iris, juno and vega (10.0.x.x) plus merry and gloin, and the five peer ids are those
     *      same nodes -- tau itself configures no direct peers, so DIRECT_PEERS is assembled from
     *      the validators' lists, which agree on every id.
     *
     *      Carries the same unresolved question as the mainnet lists: the first three entries are
     *      10.0.x.x addresses routable only inside the Neynar VPC, and publishing them in a registry
     *      that external validators read is misleading to everyone outside it. Open on C6.
     */
    string internal constant TESTNET_BOOTSTRAP_PEERS = "/ip4/10.0.0.212/udp/3382/quic-v1,"
        " /ip4/10.0.0.182/udp/3382/quic-v1, /ip4/10.0.1.229/udp/3382/quic-v1,"
        " /ip4/50.17.173.197/udp/3382/quic-v1, /ip4/13.205.232.10/udp/3382/quic-v1";

    string internal constant TESTNET_DIRECT_PEERS = "12D3KooWHTpapWmaNYxPcaWn9Uhoh7TZ67LZcM9dCUMMEwebCe7V,"
        " 12D3KooWRUQMrmZGXKQvafnqZQBPuAoV1mEFLXvkZwWtgiojhoXB, 12D3KooWFy31r6kuGGuxtAcfPzePpUTtoDo4f5gCJb3A17ximJYd,"
        " 12D3KooWBLWdvcKWCUyuFtaoFWnNWZXbRNVtF629fLHUrRJboghS, 12D3KooWPx3CCoZR7Fwg5foTkhiZEYpTdYJVbqgmbpDgzarEoKG9";

    /*//////////////////////////////////////////////////////////////
                                  SEED
    //////////////////////////////////////////////////////////////*/

    /**
     * @param validatorSets  Full validator-set history, in append order.
     * @param bootstrapPeers Comma-separated multiaddrs.
     * @param directPeers    Comma-separated peer ids.
     */
    struct Seed {
        ISnapchainConfigRegistry.ValidatorSet[] validatorSets;
        string bootstrapPeers;
        string directPeers;
    }

    /**
     * @dev Seed data for the chain this is running on.
     *
     *      Snapchain testnet runs an entirely separate validator set -- different keys, different
     *      heights, thirteen entries against mainnet's ten -- so seeding Sepolia with mainnet's
     *      history would produce a registry that is wrong in the worst available way: well-formed,
     *      renderable, and capable of taking every testnet node down on boot. Hence two branches and
     *      a revert on anything else, rather than a default.
     */
    function _seedFor(
        uint256 chainId
    ) internal pure returns (Seed memory) {
        if (chainId == ETH_MAINNET_CHAIN_ID) {
            return Seed({
                validatorSets: _mainnetValidatorSets(),
                bootstrapPeers: MAINNET_BOOTSTRAP_PEERS,
                directPeers: MAINNET_DIRECT_PEERS
            });
        }
        if (chainId == ETH_SEPOLIA_CHAIN_ID) {
            return Seed({
                validatorSets: _testnetValidatorSets(),
                bootstrapPeers: TESTNET_BOOTSTRAP_PEERS,
                directPeers: TESTNET_DIRECT_PEERS
            });
        }
        revert NoSeedDataForChain(chainId);
    }

    /**
     * @dev Snapchain mainnet's validator-set history exactly as validators.toml records it, all ten
     *      entries back to `effective_at = 0`.
     *
     *      The whole history, not just the current set: read nodes syncing from genesis verify old
     *      commit signatures against the historical entries, and `StoredValidatorSets::get_validator_set`
     *      seeds its scan with `sets[0]`, so entry 0 is load-bearing as the implicit fallback and an
     *      empty list panics on index 0.
     *
     *      Note the heights do not ascend monotonically across the array -- 26_556_206 on shard 2
     *      precedes 26_701_296 on shard 1, and the shard-0 entries run ahead of both. That is
     *      correct: `effective_at` is a per-shard height, and each shard advances on its own
     *      counter. The registry bounds an entry only against preceding entries sharing a shard.
     */
    function _mainnetValidatorSets() internal pure returns (ISnapchainConfigRegistry.ValidatorSet[] memory sets) {
        sets = new ISnapchainConfigRegistry.ValidatorSet[](10);
        sets[0] = _set(0, _shards(0, 1, 2), _keys(V1, V2, V3, V4, V5));
        sets[1] = _set(26_386_684, _shards(0), _keys(V1, V2, V3, V6, V5));
        sets[2] = _set(26_556_206, _shards(2), _keys(V1, V2, V3, V6, V5));
        sets[3] = _set(26_701_296, _shards(1), _keys(V1, V2, V3, V6, V5));
        sets[4] = _set(28_415_000, _shards(0), _keys(V1, V2, V3, V6, V5, V7));
        sets[5] = _set(28_706_000, _shards(2), _keys(V1, V2, V3, V6, V5, V7));
        sets[6] = _set(28_852_000, _shards(1), _keys(V1, V2, V3, V6, V5, V7));
        sets[7] = _set(39_180_000, _shards(0), _keys(V1, V2, V3, V6, V5, V7, V8));
        sets[8] = _set(39_624_000, _shards(2), _keys(V1, V2, V3, V6, V5, V7, V8));
        sets[9] = _set(39_798_000, _shards(1), _keys(V1, V2, V3, V6, V5, V7, V8));
    }

    /**
     * @dev Snapchain testnet's validator-set history as `snapchain-deployer/.stack/deploy.yml`
     *      records it, all thirteen entries back to `effective_at = 0`. Every testnet pod in that
     *      file -- iris, juno, vega and the tau read node -- carries a byte-identical VALIDATOR_SETS
     *      string, so there is one history rather than four to reconcile.
     *
     *      Ordered by ascending `effective_at` as the mainnet block is, which is not deploy.yml's
     *      literal order: it lists shard 1 before shard 2 in the 25_085_* and 33_4*_000 rollouts,
     *      and those pairs are transposed here. The registry bounds an entry only against preceding
     *      entries sharing a shard, and per-shard order is identical either way.
     *
     *      Five validators today: juno, iris and vega since genesis, merry from 33_145_000, gloin
     *      from 36_922_000. Verified against live commit certificates at shard heights 42_738_208 /
     *      43_002_880 / 43_012_625 on 2026-08-11, all well past the last entry, so this history is
     *      complete rather than merely current. Those certificates carry four of the five signers --
     *      quorum is 4 of 5 and gloin sits in the Neynar cluster, far enough from the others that
     *      its precommit routinely lands after quorum forms. Its own heights track the cluster.
     */
    function _testnetValidatorSets() internal pure returns (ISnapchainConfigRegistry.ValidatorSet[] memory sets) {
        sets = new ISnapchainConfigRegistry.ValidatorSet[](13);
        sets[0] = _set(0, _shards(0, 1, 2), _keys(T1, T2, T3, T4));
        sets[1] = _set(24_811_937, _shards(0), _keys(T1, T2, T3, T5));
        sets[2] = _set(25_085_320, _shards(2), _keys(T1, T2, T3, T5));
        sets[3] = _set(25_085_333, _shards(1), _keys(T1, T2, T3, T5));
        sets[4] = _set(28_681_000, _shards(0), _keys(T1, T2, T3));
        sets[5] = _set(28_955_000, _shards(1), _keys(T1, T2, T3));
        sets[6] = _set(28_955_000, _shards(2), _keys(T1, T2, T3));
        sets[7] = _set(33_145_000, _shards(0), _keys(T1, T2, T3, T6));
        sets[8] = _set(33_419_000, _shards(2), _keys(T1, T2, T3, T6));
        sets[9] = _set(33_421_000, _shards(1), _keys(T1, T2, T3, T6));
        sets[10] = _set(36_922_000, _shards(0), _keys(T1, T2, T3, T6, T7));
        sets[11] = _set(37_196_000, _shards(2), _keys(T1, T2, T3, T6, T7));
        sets[12] = _set(37_197_000, _shards(1), _keys(T1, T2, T3, T6, T7));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _set(
        uint64 effectiveAt,
        uint32[] memory shardIds,
        bytes32[] memory validatorPublicKeys
    ) internal pure returns (ISnapchainConfigRegistry.ValidatorSet memory) {
        return ISnapchainConfigRegistry.ValidatorSet({
            effectiveAt: effectiveAt,
            shardIds: shardIds,
            validatorPublicKeys: validatorPublicKeys
        });
    }

    function _shards(
        uint32 a
    ) internal pure returns (uint32[] memory shardIds) {
        shardIds = new uint32[](1);
        shardIds[0] = a;
    }

    function _shards(uint32 a, uint32 b, uint32 c) internal pure returns (uint32[] memory shardIds) {
        shardIds = new uint32[](3);
        shardIds[0] = a;
        shardIds[1] = b;
        shardIds[2] = c;
    }

    function _keys(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory k) {
        k = new bytes32[](3);
        k[0] = a;
        k[1] = b;
        k[2] = c;
    }

    function _keys(bytes32 a, bytes32 b, bytes32 c, bytes32 d) internal pure returns (bytes32[] memory k) {
        k = new bytes32[](4);
        k[0] = a;
        k[1] = b;
        k[2] = c;
        k[3] = d;
    }

    function _keys(bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e) internal pure returns (bytes32[] memory k) {
        k = new bytes32[](5);
        k[0] = a;
        k[1] = b;
        k[2] = c;
        k[3] = d;
        k[4] = e;
    }

    function _keys(
        bytes32 a,
        bytes32 b,
        bytes32 c,
        bytes32 d,
        bytes32 e,
        bytes32 f
    ) internal pure returns (bytes32[] memory k) {
        k = new bytes32[](6);
        k[0] = a;
        k[1] = b;
        k[2] = c;
        k[3] = d;
        k[4] = e;
        k[5] = f;
    }

    function _keys(
        bytes32 a,
        bytes32 b,
        bytes32 c,
        bytes32 d,
        bytes32 e,
        bytes32 f,
        bytes32 g
    ) internal pure returns (bytes32[] memory k) {
        k = new bytes32[](7);
        k[0] = a;
        k[1] = b;
        k[2] = c;
        k[3] = d;
        k[4] = e;
        k[5] = f;
        k[6] = g;
    }
}
