// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {SnapchainConfigRegistry} from "../src/SnapchainConfigRegistry.sol";
import {ISnapchainConfigRegistry} from "../src/interfaces/ISnapchainConfigRegistry.sol";
import {SnapchainConfigRegistrySeed} from "./abstract/SnapchainConfigRegistrySeed.sol";
import {console, ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

/**
 * @title DeploySnapchainConfigRegistry
 *
 * @notice Deploys a SnapchainConfigRegistry, seeds it with the config for the chain it lands on,
 *         and hands ownership to the address that will author changes from then on.
 *
 * @dev Two instances are expected, one per Snapchain network:
 *
 *      - **Mainnet** on Ethereum L1 (chain 1)
 *      - **Testnet** on Sepolia (chain 11155111)
 *
 *      Different chains rather than two addresses on one chain, so a testnet mistake cannot touch
 *      mainnet state and the rehearsal costs nothing real. With identical creation code, constructor
 *      args, and salt, the two land at the *same address on both chains* -- a convenience, not
 *      something anything should depend on, since a redeploy on either chain breaks it.
 */
contract DeploySnapchainConfigRegistry is SnapchainConfigRegistrySeed, ImmutableCreate2Deployer, Test {
    struct Salts {
        bytes32 snapchainConfigRegistry;
    }

    struct DeploymentParams {
        address deployer;
        address owner;
        Salts salts;
    }

    struct Addresses {
        address snapchainConfigRegistry;
    }

    struct Contracts {
        SnapchainConfigRegistry snapchainConfigRegistry;
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
        addrs.snapchainConfigRegistry = register(
            "SnapchainConfigRegistry",
            params.salts.snapchainConfigRegistry,
            type(SnapchainConfigRegistry).creationCode,
            // The deployer owns the registry through setup, since seeding is owner-gated. Handed off
            // at the end of runSetup.
            abi.encode(params.deployer)
        );
        deploy(broadcast);

        return Contracts({snapchainConfigRegistry: SnapchainConfigRegistry(addrs.snapchainConfigRegistry)});
    }

    /**
     * @dev Seed the full validator-set history and peer lists, then transfer ownership.
     *
     *      Ownable2Step leaves `params.owner` as `pendingOwner`; it accepts in a separate
     *      transaction. Until it does, the deployer still owns the registry -- which is the point of
     *      the two-step, but does mean the handoff is not complete when this script exits.
     */
    function runSetup(Contracts memory contracts, DeploymentParams memory params, bool broadcast) public {
        if (deploymentChanged()) {
            console.log("Running setup");

            // Read before broadcasting: on an unrecognized chain this reverts, and it should do so
            // before any transaction is sent rather than halfway through seeding.
            Seed memory seed = _seedFor(block.chainid);
            uint256 setCount = seed.validatorSets.length;

            if (broadcast) vm.startBroadcast();
            for (uint256 i; i < setCount; ++i) {
                ISnapchainConfigRegistry.ValidatorSet memory validatorSet = seed.validatorSets[i];
                contracts.snapchainConfigRegistry.appendValidatorSet(
                    validatorSet.effectiveAt, validatorSet.shardIds, validatorSet.validatorPublicKeys
                );
            }
            contracts.snapchainConfigRegistry.setBootstrapPeers(seed.bootstrapPeers);
            contracts.snapchainConfigRegistry.setDirectPeers(seed.directPeers);
            contracts.snapchainConfigRegistry.transferOwnership(params.owner);
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
            owner: vm.envAddress("SNAPCHAIN_CONFIG_REGISTRY_OWNER_ADDRESS"),
            salts: Salts({snapchainConfigRegistry: loadSalt()})
        });
    }

    /**
     * @dev One salt serves both chains by default, which puts the two registries at the same
     *      address. `SNAPCHAIN_CONFIG_REGISTRY_TESTNET_CREATE2_SALT` overrides on Sepolia if that
     *      address turns out to be taken there.
     */
    function loadSalt() internal view returns (bytes32) {
        bytes32 salt = vm.envOr("SNAPCHAIN_CONFIG_REGISTRY_CREATE2_SALT", bytes32(0));
        if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            return vm.envOr("SNAPCHAIN_CONFIG_REGISTRY_TESTNET_CREATE2_SALT", salt);
        }
        return salt;
    }
}
