// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {KeyRegistry} from "../../../src/KeyRegistry.sol";

/**
 * @dev Adding enumerable sets tracking keys in the KeyRegistry blew up the
 *      state space and triggered internal Halmos errors related to symbolic
 *      storage. This harness class overrides and simplifies internal methods
 *      that add/remove from KeySet as a workaround, enabling us to test
 *      the core state transition invariants but ignore KeySet internals.
 */
contract KeyRegistryHarness is KeyRegistry {
    constructor(
        address idRegistry,
        address migrator,
        address owner,
        uint256 maxKeysPerFid
    ) KeyRegistry(idRegistry, migrator, owner, maxKeysPerFid) {}

    mapping(uint256 fid => bytes[] activeKeys) activeKeys;

    function totalKeys(uint256 fid, KeyState) public view override returns (uint256) {
        return activeKeys[fid].length;
    }

    function _addToKeySet(uint256 fid, bytes calldata key) internal override {
        activeKeys[fid].push(key);
    }

    function _removeFromKeySet(uint256 fid, bytes calldata) internal override {
        activeKeys[fid].pop();
    }

    function _resetFromKeySet(uint256 fid, bytes calldata) internal override {
        activeKeys[fid].pop();
    }
}
