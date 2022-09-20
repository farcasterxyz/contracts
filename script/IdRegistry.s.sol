// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {IdRegistry} from "../src/IdRegistry.sol";

contract IdRegistryScript is Script {
    address private goerliTrustedForwarder = address(0x7A95fA73250dc53556d264522150A940d4C50238);

    function run() public {
        vm.broadcast();
        new IdRegistry(goerliTrustedForwarder);
    }
}
