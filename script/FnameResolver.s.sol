// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {FnameResolver} from "../src/FnameResolver.sol";

contract FnameResolverScript is Script {
    bytes32 internal constant CREATE2_SALT = "fc";

    function run() public {
        string memory serverURI = vm.envString("FNAME_RESOLVER_SERVER_URL");
        address signer = vm.envAddress("FNAME_RESOLVER_SIGNER_ADDRESS");
        address owner = vm.envAddress("FNAME_RESOLVER_OWNER_ADDRESS");

        vm.broadcast();
        new FnameResolver{ salt: CREATE2_SALT }(
            serverURI,
            signer,
            owner
        );
    }
}
