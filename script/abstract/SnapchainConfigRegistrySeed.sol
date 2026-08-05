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
     *      Sepolia deliberately has none yet. Snapchain testnet runs an entirely separate validator
     *      set -- different keys, different heights, currently 10-plus entries in
     *      `snapchain-deployer/.stack/deploy.yml` -- so seeding it with mainnet's history would
     *      produce a registry that is wrong in the worst available way: well-formed, renderable, and
     *      capable of taking every testnet node down on boot. Transcribing and verifying that data
     *      is C6's job. Reverting here is the honest placeholder.
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
