// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {
    SnapchainConfigRegistry, DeploySnapchainConfigRegistry
} from "../../script/DeploySnapchainConfigRegistry.s.sol";
import {SnapchainConfigRegistryTestSuite} from "../SnapchainConfigRegistry/SnapchainConfigRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract DeploySnapchainConfigRegistryTest is DeploySnapchainConfigRegistry, SnapchainConfigRegistryTestSuite {
    address internal registryOwner = makeAddr("registryOwner");
    address internal deployer = makeAddr("deployer");

    /// @dev The registry as the deploy script produces it.
    SnapchainConfigRegistry internal deployed;

    function setUp() public override {
        // Forked because the deploy goes through the ImmutableCreate2Factory at
        // 0x0000000000FFe8B47B3e2130213B802212439497, which only exists on real chains. Unpinned, as
        // DeployL1Test is -- nothing here reads chain state beyond that factory's code.
        vm.createSelectFork("eth_mainnet");

        // Seeds `registry`, the reference instance built by owner pranks rather than by the script.
        super.setUp();
        _seedMainnet();

        DeploySnapchainConfigRegistry.DeploymentParams memory params = DeploySnapchainConfigRegistry.DeploymentParams({
            deployer: deployer,
            owner: registryOwner,
            salts: DeploySnapchainConfigRegistry.Salts({snapchainConfigRegistry: 0})
        });

        vm.startPrank(deployer);
        DeploySnapchainConfigRegistry.Contracts memory contracts = runDeploy(params, false);
        runSetup(contracts, params, false);
        vm.stopPrank();

        deployed = contracts.snapchainConfigRegistry;
    }

    function test_deploymentParams() public {
        // Ownable2Step: the deployer still owns it until the incoming owner accepts.
        assertEq(deployed.owner(), deployer);
        assertEq(deployed.pendingOwner(), registryOwner);

        // Ten appends plus two peer setters.
        assertEq(deployed.validatorSetCount(), 10);
        assertEq(deployed.configVersion(), 12);

        assertEq(deployed.validatorSetAt(0).effectiveAt, 0);
        assertEq(deployed.validatorSetAt(0).shardIds.length, 3);
        assertEq(deployed.validatorSetAt(9).effectiveAt, 39_798_000);

        assertEq(deployed.bootstrapPeers(), MAINNET_BOOTSTRAP_PEERS);
        assertEq(deployed.directPeers(), MAINNET_DIRECT_PEERS);
    }

    /**
     * @dev The script's seeding path renders identically to the suite's.
     *
     *      Deliberately compared against the reference instance rather than against a second copy of
     *      the expected document. Both instances draw their data from `_mainnetValidatorSets()`, and
     *      the unit suite's golden test pins the reference's output to a literal, so this closes the
     *      chain -- script output equals suite output equals the checked-in expected bytes -- while
     *      leaving exactly one copy of that string in the repo.
     */
    function test_rendersIdenticallyToReferenceInstance() public {
        assertEq(deployed.configToml(), registry.configToml());
    }

    function test_ownershipHandoff() public {
        vm.prank(registryOwner);
        deployed.acceptOwnership();

        assertEq(deployed.owner(), registryOwner);
        assertEq(deployed.pendingOwner(), address(0));

        // The new owner can author changes, and the deployer can no longer.
        vm.prank(registryOwner);
        deployed.appendValidatorSet(40_000_000, _shards(0), _keys(V1, V2, V3, V6, V5, V7, V8));
        assertEq(deployed.validatorSetCount(), 11);

        vm.prank(deployer);
        vm.expectRevert("Ownable: caller is not the owner");
        deployed.appendValidatorSet(40_100_000, _shards(0), _keys(V1, V2, V3, V6, V5, V7, V8));
    }
}

/**
 * @dev The script refuses to seed a chain it has no data for.
 *
 *      Sepolia is the case that matters: Snapchain testnet runs a wholly separate validator set, so
 *      a script that silently fell back to mainnet's history would produce a well-formed registry
 *      that takes every testnet node down on boot. C6 supplies the testnet data.
 *
 *      Its own contract because ImmutableCreate2Deployer accumulates `names` in storage across
 *      `register` calls. A second deploy from a contract that already deployed one in setUp finds
 *      the first entry's address on the repeat pass, marks it FOUND, and `deploymentChanged()` then
 *      reports no change -- so runSetup would skip rather than revert, and the test would pass for
 *      the wrong reason.
 */
contract DeploySnapchainConfigRegistrySeedGateTest is DeploySnapchainConfigRegistry {
    function setUp() public {
        vm.createSelectFork("eth_mainnet");
    }

    function test_revertsSeedingUnknownChain() public {
        vm.chainId(ETH_SEPOLIA_CHAIN_ID);

        address deployer = makeAddr("deployer");
        DeploySnapchainConfigRegistry.DeploymentParams memory params = DeploySnapchainConfigRegistry.DeploymentParams({
            deployer: deployer,
            owner: makeAddr("registryOwner"),
            salts: DeploySnapchainConfigRegistry.Salts({snapchainConfigRegistry: 0})
        });

        vm.startPrank(deployer);
        DeploySnapchainConfigRegistry.Contracts memory contracts = runDeploy(params, false);

        vm.expectRevert(abi.encodeWithSelector(NoSeedDataForChain.selector, ETH_SEPOLIA_CHAIN_ID));
        this.runSetup(contracts, params, false);
        vm.stopPrank();
    }
}
