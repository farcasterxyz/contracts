// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Script.sol";

import {FnameResolver} from "../src/FnameResolver.sol";
import {ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

contract FnameResolverScript is ImmutableCreate2Deployer {
    function run() public {
        string memory serverURI = vm.envString("FNAME_RESOLVER_SERVER_URL");
        address signer = vm.envAddress("FNAME_RESOLVER_SIGNER_ADDRESS");
        address owner = vm.envAddress("FNAME_RESOLVER_OWNER_ADDRESS");

        register("FnameResolver", type(FnameResolver).creationCode, abi.encode(serverURI, signer, owner));
        deploy();
    }
}
