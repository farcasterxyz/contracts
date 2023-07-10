// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IdRegistry} from "../../src/IdRegistry.sol";

/**
 * @dev This "fabricator" contract allows us to deploy the `IdRegistry` using CREATE2
 *      and atomically transfer ownership. Otherwise, the CREATE2 deployer address
 *      will be the initial owner.
 */
contract IdRegistryFab {
    address public immutable registryAddr;

    constructor(address initialOwner, bytes32 salt) {
        IdRegistry registry = new IdRegistry{ salt: salt }();
        registry.transferOwnership(initialOwner);
        registryAddr = address(registry);
    }
}
