// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {TierRegistry} from "../src/TierRegistry.sol";
import {console, ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

contract DeployTierRegistry is ImmutableCreate2Deployer, Test {
    address public constant BASE_USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    uint256 public constant MIN_DAYS = 30;
    uint256 public constant MAX_DAYS = 365;
    uint256 public constant PRICE_PER_DAY = 328768;

    struct Salts {
        bytes32 tierRegistry;
    }

    struct DeploymentParams {
        address deployer;
        address vault;
        address owner;
        address migrator;
        Salts salts;
    }

    struct Addresses {
        address tierRegistry;
    }

    struct Contracts {
        TierRegistry tierRegistry;
    }

    function run() public {
        runSetup(runDeploy(loadDeploymentParams()));
    }

    function runDeploy(
        DeploymentParams memory params
    ) public returns (Contracts memory) {
        return runDeploy(params, true);
    }

    function runDeploy(DeploymentParams memory params, bool broadcast) public returns (Contracts memory) {
        Addresses memory addrs;
        addrs.tierRegistry = register(
            "TierRegistry",
            params.salts.tierRegistry,
            type(TierRegistry).creationCode,
            abi.encode(params.migrator, params.deployer)
        );
        deploy(broadcast);

        return Contracts({tierRegistry: TierRegistry(addrs.tierRegistry)});
    }

    function runSetup(Contracts memory contracts, DeploymentParams memory params, bool broadcast) public {
        if (deploymentChanged()) {
            console.log("Running setup");

            if (broadcast) vm.startBroadcast();
            contracts.tierRegistry.setTier(1, BASE_USDC, MIN_DAYS, MAX_DAYS, PRICE_PER_DAY, params.vault);
            contracts.tierRegistry.transferOwnership(params.owner);
            if (broadcast) vm.stopBroadcast();
        } else {
            console.log("No changes, skipping setup");
        }
    }

    function runSetup(
        Contracts memory contracts
    ) public {
        DeploymentParams memory params = loadDeploymentParams();
        runSetup(contracts, params, true);
    }

    function loadDeploymentParams() internal returns (DeploymentParams memory) {
        return DeploymentParams({
            deployer: vm.envAddress("DEPLOYER"),
            vault: vm.envAddress("TIER_REGISTRY_VAULT_ADDRESS"),
            owner: vm.envAddress("TIER_REGISTRY_OWNER_ADDRESS"),
            migrator: vm.envAddress("TIER_REGISTRY_MIGRATOR_ADDRESS"),
            salts: Salts({tierRegistry: vm.envOr("TIER_REGISTRY_CREATE2_SALT", bytes32(0))})
        });
    }
}
