// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {SnapchainConfigRegistry} from "../../src/SnapchainConfigRegistry.sol";
import {ISnapchainConfigRegistry} from "../../src/interfaces/ISnapchainConfigRegistry.sol";
import {SnapchainConfigRegistrySeed} from "../../script/abstract/SnapchainConfigRegistrySeed.sol";

/**
 * @dev Mainnet seed data -- the keys, the peer strings, and the ten-entry history -- lives in
 *      SnapchainConfigRegistrySeed alongside the deploy script that writes it, so the golden test
 *      below pins the literal bytes that get deployed rather than a parallel copy that can drift.
 */
abstract contract SnapchainConfigRegistryTestSuite is SnapchainConfigRegistrySeed, TestSuiteSetup {
    SnapchainConfigRegistry internal registry;

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

    function _shards(uint32 a, uint32 b) internal pure returns (uint32[] memory shardIds) {
        shardIds = new uint32[](2);
        shardIds[0] = a;
        shardIds[1] = b;
    }

    /**
     * @dev Seed the registry with the same data the deploy script writes on Ethereum L1, applied
     *      here as owner pranks rather than broadcasts.
     */
    function _seedMainnet() internal {
        Seed memory seed = _seedFor(ETH_MAINNET_CHAIN_ID);

        uint256 setCount = seed.validatorSets.length;
        for (uint256 i; i < setCount; ++i) {
            ISnapchainConfigRegistry.ValidatorSet memory validatorSet = seed.validatorSets[i];
            _append(validatorSet.effectiveAt, validatorSet.shardIds, validatorSet.validatorPublicKeys);
        }

        vm.startPrank(owner);
        registry.setBootstrapPeers(seed.bootstrapPeers);
        registry.setDirectPeers(seed.directPeers);
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
