// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {IdRegistryFab} from "./helpers/IdRegistryFab.sol";

contract IdRegistryScript is Script {
    bytes32 internal constant CREATE2_SALT = "fc";

    function run() public {
        address trustedForwarder = vm.envAddress("ID_REGISTRY_TRUSTED_FORWARDER_ADDRESS");
        address initialOwner = vm.envAddress("ID_REGISTRY_OWNER_ADDRESS");

        vm.broadcast();
        new IdRegistryFab(trustedForwarder, initialOwner, CREATE2_SALT);
    }
}
