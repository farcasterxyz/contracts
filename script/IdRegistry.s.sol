// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {IdRegistry} from "../src/IdRegistry.sol";

contract IdRegistryScript is Script {
    bytes32 internal constant CREATE2_SALT = "fc";

    function run() public {
        address initialOwner = vm.envAddress("ID_REGISTRY_OWNER_ADDRESS");

        vm.broadcast();
        new IdRegistry{ salt: CREATE2_SALT }(initialOwner);
    }
}
