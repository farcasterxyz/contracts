// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Script.sol";

import {BundleRegistry} from "../src/BundleRegistry.sol";
import {IDRegistry} from "../src/IDRegistry.sol";
import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility*/
/* solhint-disable avoid-low-level-calls */

contract BundleRegistryScript is Script {
    address constant GOERLI_FORWARDER = address(0x7A95fA73250dc53556d264522150A940d4C50238);
    address constant ADMIN = address(0x973Eff2C8eBC79bECb9937fC42E65D96aCCB3ADd);

    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    ERC1967Proxy proxy;
    IDRegistry idRegistry;

    // TODO: Fix the vault and pool address
    address constant VAULT = ADMIN;
    address constant POOL = ADMIN;

    function run() public {
        vm.broadcast();
        idRegistry = new IDRegistry(GOERLI_FORWARDER);

        vm.broadcast();
        nameRegistryImpl = new NameRegistry(GOERLI_FORWARDER);

        vm.broadcast();
        proxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(proxy));

        vm.broadcast();
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);

        vm.broadcast();
        new BundleRegistry(address(idRegistry), address(nameRegistry), ADMIN);
    }
}
