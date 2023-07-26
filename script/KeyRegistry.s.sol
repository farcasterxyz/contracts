// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";

contract IdRegistryScript is Script {
    bytes32 internal constant CREATE2_SALT = "fc";
    uint24 internal constant KEY_REGISTRY_MIGRATION_GRACE_PERIOD = 1 days;

    function run() public {
        address idRegistry = vm.envAddress("ID_REGISTRY_ADDRESS");
        address initialOwner = vm.envAddress("KEY_REGISTRY_OWNER_ADDRESS");

        vm.broadcast();
        new KeyRegistry{ salt: CREATE2_SALT }(
            address(idRegistry),
            KEY_REGISTRY_MIGRATION_GRACE_PERIOD,
            initialOwner
        );
    }
}
