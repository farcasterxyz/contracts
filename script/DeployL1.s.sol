// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FnameResolver} from "../src/FnameResolver.sol";
import {console, ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

contract DeployL1 is ImmutableCreate2Deployer {
    bytes32 internal constant FNAME_RESOLVER_CREATE2_SALT = bytes32(0);

    struct DeploymentParams {
        bytes name;
        address resolver;
        string serverURL;
        address signer;
        address owner;
        address deployer;
    }

    struct Contracts {
        FnameResolver fnameResolver;
    }

    function run() public {
        runDeploy(loadDeploymentParams());
    }

    function runDeploy(
        DeploymentParams memory params
    ) public returns (Contracts memory) {
        return runDeploy(params, true);
    }

    function runDeploy(DeploymentParams memory params, bool broadcast) public returns (Contracts memory) {
        address fnameResolver = register(
            "FnameResolver",
            FNAME_RESOLVER_CREATE2_SALT,
            type(FnameResolver).creationCode,
            abi.encode(params.name, params.resolver, params.serverURL, params.signer, params.owner)
        );

        deploy(broadcast);

        return Contracts({fnameResolver: FnameResolver(fnameResolver)});
    }

    function loadDeploymentParams() internal view returns (DeploymentParams memory) {
        return DeploymentParams({
            name: vm.envBytes("FNAME_RESOLVER_DNS_ENCODED_NAME"),
            resolver: vm.envAddress("FNAME_RESOLVER_PASSTHROUGH_ADDRESS"),
            serverURL: vm.envString("FNAME_RESOLVER_SERVER_URL"),
            signer: vm.envAddress("FNAME_RESOLVER_SIGNER_ADDRESS"),
            owner: vm.envAddress("FNAME_RESOLVER_OWNER_ADDRESS"),
            deployer: vm.envAddress("DEPLOYER")
        });
    }
}
