// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {KeyRegistry} from "../src/KeyRegistry.sol";
import {ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

contract IdRegistryScript is ImmutableCreate2Deployer {
    uint24 internal constant KEY_REGISTRY_MIGRATION_GRACE_PERIOD = 1 days;

    function run() public {
        address idRegistry = vm.envAddress("ID_REGISTRY_ADDRESS");
        address initialOwner = vm.envAddress("KEY_REGISTRY_OWNER_ADDRESS");

        register(
            "KeyRegistry",
            type(KeyRegistry).creationCode,
            abi.encode(idRegistry, KEY_REGISTRY_MIGRATION_GRACE_PERIOD, initialOwner)
        );

        deploy();
    }
}
