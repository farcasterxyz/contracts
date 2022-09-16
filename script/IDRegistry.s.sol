// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {IdRegistry} from "../src/IdRegistry.sol";

contract IdRegistryScript is Script {
    address gorliTrustedForwarder = address(0x7A95fA73250dc53556d264522150A940d4C50238);

    // TODO: coverage does not like empty functions, and I can't remember if this was important to the deploy
    // Retaining this until we can remove safely.
    function setUp() public {}

    function run() public {
        vm.broadcast();
        new IdRegistry(gorliTrustedForwarder);
    }
}
