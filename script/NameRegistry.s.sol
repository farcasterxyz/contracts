// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";

import {NameRegistry} from "../src/NameRegistry.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* solhint-disable state-visibility*/
/* solhint-disable avoid-low-level-calls */

contract NameRegistryScript is Script {
    address gorliTrustedForwarder = address(0x7A95fA73250dc53556d264522150A940d4C50238);
    NameRegistry nameRegistry;
    ERC1967Proxy proxy;

    address owner = address(0x123);
    address vault = address(0x123);
    address preregistrar = address(0x123);

    function setUp() public {}

    function run() public {
        vm.broadcast();
        nameRegistry = new NameRegistry(gorliTrustedForwarder);

        vm.broadcast();
        new ERC1967Proxy(address(nameRegistry), "");

        vm.broadcast();
        (bool s, ) = address(proxy).call(
            abi.encodeWithSelector(
                nameRegistry.initialize.selector,
                "Farcaster NameRegistry",
                "FCN",
                owner,
                vault,
                preregistrar
            )
        );
    }
}
