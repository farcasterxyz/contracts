// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {BundleRegistry} from "../src/BundleRegistry.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable no-empty-blocks */

/**
 * @dev IdRegistryHarness exposes IdRegistry's private methods for test assertions.
 */
contract IdRegistryHarness is IdRegistry {
    constructor(address forwarder) IdRegistry(forwarder) {}

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
 * @dev NameRegistryHarness exposes NameRegistry's struct values with concise accessors for testing.
 */
contract NameRegistryHarness is NameRegistry {
    constructor(address forwarder) NameRegistry(forwarder) {}

    /// @dev Get the recovery address for a tokenId
    function recoveryOf(uint256 tokenId) public view returns (address) {
        return metadataOf[tokenId].recovery;
    }

    /// @dev Get the expiry timestamp for a tokenId
    function expiryTsOf(uint256 tokenId) public view returns (uint256) {
        return metadataOf[tokenId].expiryTs;
    }

    /// @dev Get the recovery destination for a tokenId
    function recoveryDestinationOf(uint256 tokenId) public view returns (address) {
        return recoveryStateOf[tokenId].recoveryDestination;
    }

    /// @dev Get the recovery timestamp for a tokenId
    function recoveryTsOf(uint256 tokenId) public view returns (uint256) {
        return recoveryStateOf[tokenId].recoveryTs;
    }
}

/**
 * @dev BundleRegistryHarness exposes IdRegistry's private methods for test assertions.
 */
contract BundleRegistryHarness is BundleRegistry {
    constructor(
        address idRegistry,
        address nameRegistry,
        address trustedCaller
    ) BundleRegistry(idRegistry, nameRegistry, trustedCaller) {}

    function getTrustedCaller() public view returns (address) {
        return trustedCaller;
    }
}
