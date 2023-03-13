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

    function getRecoveryTsOf(uint256 id) public view returns (uint256) {
        return uint256(recoveryStateOf[id].startTs);
    }

    function getRecoveryDestinationOf(uint256 id) public view returns (address) {
        return recoveryStateOf[id].destination;
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
        return uint256(metadataOf[tokenId].expiryTs);
    }

    /// @dev Get the recovery destination for a tokenId
    function recoveryDestinationOf(uint256 tokenId) public view returns (address) {
        return recoveryStateOf[tokenId].destination;
    }

    /// @dev Get the recovery timestamp for a tokenId
    function recoveryTsOf(uint256 tokenId) public view returns (uint256) {
        return uint256(recoveryStateOf[tokenId].startTs);
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

/**
 * @dev Helper struct for invariant tests.
 */
struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}

/**
 * @dev Helper library for invariant tests.
 */
library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
    }

    function contains(AddressSet storage s, address addr) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }

    function rand(AddressSet storage s, uint256 seed) internal view returns (address) {
        if (s.addrs.length > 0) {
            return s.addrs[seed % s.addrs.length];
        } else {
            return address(0);
        }
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(
        AddressSet storage s,
        uint256 acc,
        function(uint256,address) external returns (uint256) func
    ) internal returns (uint256) {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }
}
