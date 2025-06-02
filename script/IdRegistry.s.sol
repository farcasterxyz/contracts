// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IdRegistry} from "../src/IdRegistry.sol";
import {ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

contract IdRegistryScript is ImmutableCreate2Deployer {
    function run() public {
        address initialOwner = vm.envAddress("ID_REGISTRY_OWNER_ADDRESS");

        register("IdRegistry", type(IdRegistry).creationCode, abi.encode(initialOwner));
        deploy();
    }
}
