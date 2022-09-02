// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;
import {IDRegistry} from "../src/IDRegistry.sol";
import {BundleRegistry} from "../src/BundleRegistry.sol";

/**
 * @dev IDRegistryTestable exposes IDRegistry's private methods for test assertions.
 */
contract IDRegistryTestable is IDRegistry {
    // solhint-disable-next-line no-empty-blocks
    constructor(address forwarder) IDRegistry(forwarder) {}

    function idOf(address addr) public view returns (uint256) {
        return _idOf[addr];
    }

    function recoveryOf(uint256 id) public view returns (address) {
        return _recoveryOf[id];
    }

    function recoveryClockOf(uint256 id) public view returns (uint256) {
        return _recoveryClockOf[id];
    }

    function recoveryDestinationOf(uint256 id) public view returns (address) {
        return _recoveryDestinationOf[id];
    }

    function trustedSender() public view returns (address) {
        return _trustedSender;
    }

    function trustedRegisterEnabled() public view returns (uint256) {
        return _trustedRegisterEnabled;
    }
}

/**
 * @dev BundleRegistryTestable exposes IDRegistry's private methods for test assertions.
 */
contract BundleRegistryTestable is BundleRegistry {
    constructor(
        address idRegistry,
        address nameRegistry,
        address trustedSender
    ) BundleRegistry(idRegistry, nameRegistry, trustedSender) {}

    function getTrustedSender() public view returns (address) {
        return trustedSender;
    }
}
