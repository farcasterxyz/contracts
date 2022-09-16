// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BundleRegistry} from "../src/BundleRegistry.sol";
import {IDRegistry} from "../src/IDRegistry.sol";

/* solhint-disable no-empty-blocks */

/**
 * @dev IDRegistryTestable exposes IDRegistry's private methods for test assertions.
 */
contract IDRegistryTestable is IDRegistry {
    constructor(address forwarder) IDRegistry(forwarder) {}

    function getIdCounter() public view returns (uint256) {
        return idCounter;
    }

    function getRecoveryOf(uint256 id) public view returns (address) {
        return recoveryOf[id];
    }

    function setRecoveryClockOf(uint256 id, uint256 timestamp) public {
        recoveryClockOf[id] = timestamp;
    }

    function getRecoveryClockOf(uint256 id) public view returns (uint256) {
        return recoveryClockOf[id];
    }

    function getRecoveryDestinationOf(uint256 id) public view returns (address) {
        return recoveryDestinationOf[id];
    }

    function getTrustedCaller() public view returns (address) {
        return trustedCaller;
    }

    function getTrustedOnly() public view returns (uint256) {
        return trustedOnly;
    }

    function getPendingOwner() public view returns (address) {
        return pendingOwner;
    }
}

/**
 * @dev BundleRegistryTestable exposes IDRegistry's private methods for test assertions.
 */
contract BundleRegistryTestable is BundleRegistry {
    constructor(
        address idRegistry,
        address nameRegistry,
        address trustedCaller
    ) BundleRegistry(idRegistry, nameRegistry, trustedCaller) {}

    function getTrustedCaller() public view returns (address) {
        return trustedCaller;
    }
}
