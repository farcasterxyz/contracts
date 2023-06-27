// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IdRegistry} from "../src/IdRegistry.sol";

contract IdRegistryFab {
    constructor(address trustedForwarder, address initialOwner, bytes32 salt) {
        IdRegistry registry = new IdRegistry{ salt: salt }(trustedForwarder);
        registry.requestTransferOwnership(initialOwner);
    }
}

contract IdRegistryScript is Script {
    bytes32 internal constant CREATE2_SALT = "fc";

    function run() public {
        address trustedForwarder = vm.envAddress("ID_REGISTRY_TRUSTED_FORWARDER_ADDRESS");
        address initialOwner = vm.envAddress("ID_REGISTRY_OWNER_ADDRESS");

        vm.broadcast();
        new IdRegistryFab(trustedForwarder, initialOwner, CREATE2_SALT);
    }
}
