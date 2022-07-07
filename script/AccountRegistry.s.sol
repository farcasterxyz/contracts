// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";

import {AccountRegistry} from "../src/AccountRegistry.sol";

contract AccountRegistryScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        new AccountRegistry();
    }
}
