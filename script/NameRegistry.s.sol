// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Script.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility*/

contract NameRegistryScript is Script {
    address goerliTrustedForwarder = address(0x7A95fA73250dc53556d264522150A940d4C50238);
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistryProxy;
    ERC1967Proxy proxy;

    // TODO: Fix the vault and pool address
    address constant VAULT = address(0x123);
    address constant POOL = address(0x456);

    function run() public {
        vm.broadcast();
        nameRegistryImpl = new NameRegistry(goerliTrustedForwarder);

        vm.broadcast();
        proxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistryProxy = NameRegistry(address(proxy));

        vm.broadcast();
        nameRegistryProxy.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
    }
}
