// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry} from "../src/IdRegistry.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";
import {ImmutableCreate2Deployer} from "./lib/ImmutableCreate2Deployer.sol";

contract IdRegistryScript is ImmutableCreate2Deployer {
    uint24 internal constant KEY_REGISTRY_MIGRATION_GRACE_PERIOD = 1 days;

    function run() public {
        address initialIdRegistryOwner = vm.envAddress("ID_REGISTRY_OWNER_ADDRESS");
        address initialKeyRegistryOwner = vm.envAddress("KEY_REGISTRY_OWNER_ADDRESS");

        address idRegistry = register("IdRegistry", type(IdRegistry).creationCode, abi.encode(initialIdRegistryOwner));

        register(
            "KeyRegistry",
            type(KeyRegistry).creationCode,
            abi.encode(idRegistry, KEY_REGISTRY_MIGRATION_GRACE_PERIOD, initialKeyRegistryOwner)
        );

        deploy();
    }
}
