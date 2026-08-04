// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {SnapchainConfigRegistry} from "../../src/SnapchainConfigRegistry.sol";

abstract contract SnapchainConfigRegistryTestSuite is TestSuiteSetup {
    SnapchainConfigRegistry internal registry;

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

    // Gossip peers as configured on one Snapchain mainnet validator today. Every node currently
    // runs its own list, each omitting itself, so there is no single canonical pair to seed; these
    // are here to exercise the renderer and the peer-string allowlist against real values.
    string internal constant MAINNET_BOOTSTRAP_PEERS = "/ip4/10.0.0.148/udp/3382/quic-v1,"
        " /ip4/10.0.2.165/udp/3382/quic-v1, /ip4/107.20.169.236/udp/3382/quic-v1,"
        " /ip4/54.157.62.17/udp/3382/quic-v1, /ip4/34.4.32.36/udp/3382/quic-v1,"
        " /ip4/108.132.114.186/udp/3382/quic-v1, /ip4/100.30.67.21/udp/3382/quic-v1";

    string internal constant MAINNET_DIRECT_PEERS = "12D3KooWGmXDC2SfjSG7h7DchyVJHMB4GpA8JYpHf9iwz8L8BFqB,"
        " 12D3KooWJVyaQRovV1rjV8TzkN3cRiysACyey86kXDLdvf6JRq5Z, 12D3KooWCc28TYrrXFivwUshyZ8R5HqPMgx4f7AP54iCDLYr7kFR,"
        " 12D3KooWQaoBw2gvdmfGdXjepEQU9i47FXxvsCZ6wu8Vn4gwvHm2, 12D3KooWJVJwgRAitzcdSFmjK8AVVyzFMc5BVKTuUJk2j71nTAMu,"
        " 12D3KooWDHG75L7M8t45d6moKhnhLHgM9BYt1PBTgZfYEgsXXUa9";

    function setUp() public virtual override {
        super.setUp();

        registry = new SnapchainConfigRegistry(owner);
        addKnownContract(address(registry));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _append(uint64 effectiveAt, uint32[] memory shardIds, bytes32[] memory keys) internal {
        vm.prank(owner);
        registry.appendValidatorSet(effectiveAt, shardIds, keys);
    }

    function _amend(uint64 effectiveAt, uint32[] memory shardIds, bytes32[] memory keys) internal {
        vm.prank(owner);
        registry.amendLatestValidatorSet(effectiveAt, shardIds, keys);
    }

    /// @dev `n` distinct non-zero keys, deterministic in `n` and `salt`.
    function _distinctKeys(uint256 n, uint256 salt) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            keys[i] = keccak256(abi.encode(salt, i));
        }
    }

    function _distinctKeys(
        uint256 n
    ) internal pure returns (bytes32[] memory) {
        return _distinctKeys(n, 0);
    }

    function _shards(
        uint32 a
    ) internal pure returns (uint32[] memory shardIds) {
        shardIds = new uint32[](1);
        shardIds[0] = a;
    }

    function _shards(uint32 a, uint32 b) internal pure returns (uint32[] memory shardIds) {
        shardIds = new uint32[](2);
        shardIds[0] = a;
        shardIds[1] = b;
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

    /**
     * @dev Seed the registry with Snapchain mainnet's validator-set history and peer lists, exactly
     *      as validators.toml records it.
     *
     *      A follow-up change moves this into the deploy script and has the golden test inherit it
     *      from there, so that the test pins the literal bytes that get deployed rather than a
     *      parallel copy that can drift.
     */
    function _seedMainnet() internal {
        _append(0, _shards(0, 1, 2), _keys(V1, V2, V3, V4, V5));
        _append(26_386_684, _shards(0), _keys(V1, V2, V3, V6, V5));
        _append(26_556_206, _shards(2), _keys(V1, V2, V3, V6, V5));
        _append(26_701_296, _shards(1), _keys(V1, V2, V3, V6, V5));
        _append(28_415_000, _shards(0), _keys(V1, V2, V3, V6, V5, V7));
        _append(28_706_000, _shards(2), _keys(V1, V2, V3, V6, V5, V7));
        _append(28_852_000, _shards(1), _keys(V1, V2, V3, V6, V5, V7));
        _append(39_180_000, _shards(0), _keys(V1, V2, V3, V6, V5, V7, V8));
        _append(39_624_000, _shards(2), _keys(V1, V2, V3, V6, V5, V7, V8));
        _append(39_798_000, _shards(1), _keys(V1, V2, V3, V6, V5, V7, V8));

        vm.startPrank(owner);
        registry.setBootstrapPeers(MAINNET_BOOTSTRAP_PEERS);
        registry.setDirectPeers(MAINNET_DIRECT_PEERS);
        vm.stopPrank();
    }

    /// @dev Number of non-overlapping occurrences of `needle` in `haystack`.
    function _count(string memory haystack, string memory needle) internal pure returns (uint256 total) {
        bytes memory hay = bytes(haystack);
        bytes memory pin = bytes(needle);
        if (pin.length == 0 || pin.length > hay.length) return 0;

        for (uint256 i; i <= hay.length - pin.length;) {
            bool matched = true;
            for (uint256 j; j < pin.length; ++j) {
                if (hay[i + j] != pin[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                ++total;
                i += pin.length;
            } else {
                ++i;
            }
        }
    }

    /// @dev A one-character string built from a raw byte, so control bytes can be tested.
    function _oneChar(
        uint8 char
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(bytes1(char)));
    }
}
