// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Script.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility*/
/* solhint-disable avoid-low-level-calls */

contract NameRegistryScript is Script {
    address gorliTrustedForwarder = address(0x7A95fA73250dc53556d264522150A940d4C50238);
    NameRegistry nameRegistry;
    NameRegistry proxiedNameRegistry;
    ERC1967Proxy proxy;

    // TODO: Fix the vault and pool address
    address constant VAULT = address(0x123);
    address constant POOL = address(0x456);

    function run() public {
        vm.broadcast();
        nameRegistry = new NameRegistry(gorliTrustedForwarder);

        vm.broadcast();
        proxy = new ERC1967Proxy(address(nameRegistry), "");
        proxiedNameRegistry = NameRegistry(address(proxy));

        vm.broadcast();
        proxiedNameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
    }
}
