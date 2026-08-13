// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {
    SnapchainConfigRegistry, DeploySnapchainConfigRegistry
} from "../../script/DeploySnapchainConfigRegistry.s.sol";
import {ISnapchainConfigRegistry} from "../../src/interfaces/ISnapchainConfigRegistry.sol";
import {SnapchainConfigRegistryTestSuite} from "../SnapchainConfigRegistry/SnapchainConfigRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract DeploySnapchainConfigRegistryTest is DeploySnapchainConfigRegistry, SnapchainConfigRegistryTestSuite {
    address internal registryOwner = makeAddr("registryOwner");
    address internal deployer = makeAddr("deployer");

    /// @dev The registry as the deploy script produces it.
    SnapchainConfigRegistry internal deployed;

    function setUp() public override {
        // Forked because the deploy goes through the canonical CREATE2 proxy at
        // 0x4e59b44847b379578588920cA78FbF26c0B4956C, which only exists on real chains. Unpinned, as
        // DeployL1Test is -- nothing here reads chain state beyond that proxy's code.
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

    /**
     * @dev Re-running the script against an already-deployed registry changes nothing.
     *
     *      The idempotency claim is the reason `deploy()` checks for existing code and setup is
     *      gated on `configVersion()`, and every other test here exercises only the first-run
     *      branch. It matters because the second run is the dangerous one: seeding again would
     *      append the ten-entry history a second time, and re-running `transferOwnership` after the
     *      owner had accepted would quietly hand the registry back to the deployer.
     *
     *      Deployed from a fresh script instance rather than reusing `this`, because
     *      ImmutableCreate2Deployer accumulates `names` and `contracts` in storage. A real re-run
     *      is a new process with that state empty, and reusing `this` would test a different thing.
     */
    function test_reRunIsIdempotent() public {
        DeploySnapchainConfigRegistry rerun = new DeploySnapchainConfigRegistry();

        DeploySnapchainConfigRegistry.DeploymentParams memory params = DeploySnapchainConfigRegistry.DeploymentParams({
            deployer: deployer,
            owner: registryOwner,
            salts: DeploySnapchainConfigRegistry.Salts({snapchainConfigRegistry: 0})
        });

        vm.startPrank(deployer);
        DeploySnapchainConfigRegistry.Contracts memory contracts = rerun.runDeploy(params, false);
        rerun.runSetup(contracts, params, false);
        vm.stopPrank();

        // Same address found, not a second instance deployed.
        assertEq(address(contracts.snapchainConfigRegistry), address(deployed));

        // Setup skipped: no duplicate history, no extra version bumps, no repeated handoff.
        assertEq(deployed.validatorSetCount(), 10);
        assertEq(deployed.configVersion(), 12);
        assertEq(deployed.owner(), deployer);
        assertEq(deployed.pendingOwner(), registryOwner);
        assertEq(deployed.configToml(), registry.configToml());
    }

    /**
     * @dev `loadDeploymentParams` and the chain-dependent salt selection, which nothing else calls.
     *
     *      Worth exercising because the failure mode is invisible until broadcast: a typo in a
     *      variable name reads as "unset", and `vm.envOr` then silently supplies `bytes32(0)` -- not
     *      the mined address, and a salt so well known that the address may already be taken.
     *
     *      Written as one function, in this order, on purpose. `vm.setEnv` writes the process
     *      environment and there is no way to unset a variable afterwards, so the "no override
     *      configured" case has to be asserted before anything sets the override.
     */
    function test_loadsParamsAndSelectsSaltByChain() public {
        bytes32 sharedSalt = bytes32(uint256(0xa11ce));
        bytes32 testnetSalt = bytes32(uint256(0xb0b));

        vm.setEnv("DEPLOYER", vm.toString(deployer));
        vm.setEnv("SNAPCHAIN_CONFIG_REGISTRY_OWNER_ADDRESS", vm.toString(registryOwner));
        vm.setEnv("SNAPCHAIN_CONFIG_REGISTRY_CREATE2_SALT", vm.toString(sharedSalt));

        DeploySnapchainConfigRegistry.DeploymentParams memory params = loadDeploymentParams();
        assertEq(params.deployer, deployer);
        assertEq(params.owner, registryOwner);
        assertEq(params.salts.snapchainConfigRegistry, sharedSalt);

        // Sepolia falls back to the shared salt while no override is configured, which is what puts
        // both registries at the same address.
        vm.chainId(ETH_SEPOLIA_CHAIN_ID);
        assertEq(loadDeploymentParams().salts.snapchainConfigRegistry, sharedSalt);

        // ...and prefers the override once one exists.
        vm.setEnv("SNAPCHAIN_CONFIG_REGISTRY_TESTNET_CREATE2_SALT", vm.toString(testnetSalt));
        assertEq(loadDeploymentParams().salts.snapchainConfigRegistry, testnetSalt);

        // The override is Sepolia-only and must not leak onto mainnet.
        vm.chainId(ETH_MAINNET_CHAIN_ID);
        assertEq(loadDeploymentParams().salts.snapchainConfigRegistry, sharedSalt);
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
 *      The two seeded chains carry wholly separate validator sets, so a script that silently fell
 *      back to either one's history on a third chain would produce a well-formed, renderable
 *      registry capable of taking every node reading it down on boot. OP mainnet stands in for that
 *      third chain: a plausible destination for a Farcaster contract, and one this registry has no
 *      data for.
 *
 *      Its own contract because ImmutableCreate2Deployer accumulates `names` in storage across
 *      `register` calls. A second deploy from a contract that already deployed one in setUp finds
 *      the first entry's address on the repeat pass, and that registry is already seeded -- so
 *      runSetup would skip rather than revert, and the test would pass for the wrong reason.
 */
contract DeploySnapchainConfigRegistrySeedGateTest is DeploySnapchainConfigRegistry {
    uint256 internal constant OP_MAINNET_CHAIN_ID = 10;

    function setUp() public {
        vm.createSelectFork("eth_mainnet");
    }

    function test_revertsSeedingUnknownChain() public {
        vm.chainId(OP_MAINNET_CHAIN_ID);

        address deployer = makeAddr("deployer");
        DeploySnapchainConfigRegistry.DeploymentParams memory params = DeploySnapchainConfigRegistry.DeploymentParams({
            deployer: deployer,
            owner: makeAddr("registryOwner"),
            salts: DeploySnapchainConfigRegistry.Salts({snapchainConfigRegistry: 0})
        });

        vm.startPrank(deployer);
        DeploySnapchainConfigRegistry.Contracts memory contracts = runDeploy(params, false);

        vm.expectRevert(abi.encodeWithSelector(NoSeedDataForChain.selector, OP_MAINNET_CHAIN_ID));
        this.runSetup(contracts, params, false);
        vm.stopPrank();
    }
}

/**
 * @dev The Sepolia branch seeds Snapchain testnet's history, not mainnet's.
 *
 *      Forked from mainnet with the chain id overridden rather than forked from Sepolia, because
 *      what is under test is `_seedFor`'s branch on `block.chainid` -- the only chain state either
 *      path touches is the CREATE2 proxy's code, which is byte-identical on both. Its own contract
 *      for the same storage-accumulation reason as the seed gate test above.
 */
contract DeploySnapchainConfigRegistryTestnetSeedTest is DeploySnapchainConfigRegistry {
    address internal registryOwner = makeAddr("registryOwner");
    address internal deployer = makeAddr("deployer");

    SnapchainConfigRegistry internal deployed;

    function setUp() public {
        vm.createSelectFork("eth_mainnet");
        vm.chainId(ETH_SEPOLIA_CHAIN_ID);

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

    function test_seedsTestnetHistory() public {
        // Thirteen appends plus two peer setters.
        assertEq(deployed.validatorSetCount(), 13);
        assertEq(deployed.configVersion(), 15);

        assertEq(deployed.bootstrapPeers(), TESTNET_BOOTSTRAP_PEERS);
        assertEq(deployed.directPeers(), TESTNET_DIRECT_PEERS);

        // Genesis: all shards, four validators, one of which (T4) is long retired.
        assertEq(deployed.validatorSetAt(0).effectiveAt, 0);
        assertEq(deployed.validatorSetAt(0).shardIds.length, 3);
        assertEq(deployed.validatorSetAt(0).validatorPublicKeys.length, 4);
        assertEq(deployed.validatorSetAt(0).validatorPublicKeys[3], T4);

        // Current: five validators, gloin last in.
        assertEq(deployed.validatorSetAt(12).effectiveAt, 37_197_000);
        assertEq(deployed.validatorSetAt(12).validatorPublicKeys.length, 5);
        assertEq(deployed.validatorSetAt(12).validatorPublicKeys[4], T7);
    }

    /**
     * @dev The whole point of the branch: no mainnet key reaches a testnet registry.
     *
     *      A registry seeded with the wrong network's set is not a recoverable mistake -- history is
     *      append-only, so the remedy is a redeploy at a fresh salt and a repoint of every node.
     *      Worth asserting directly rather than trusting the counts above to catch it.
     */
    function test_holdsNoMainnetKeys() public {
        bytes32[8] memory mainnetKeys = [V1, V2, V3, V4, V5, V6, V7, V8];

        ISnapchainConfigRegistry.ValidatorSet[] memory sets = deployed.validatorSets();
        for (uint256 i; i < sets.length; ++i) {
            for (uint256 j; j < sets[i].validatorPublicKeys.length; ++j) {
                for (uint256 k; k < mainnetKeys.length; ++k) {
                    assertTrue(sets[i].validatorPublicKeys[j] != mainnetKeys[k]);
                }
            }
        }
    }
}

/**
 * @dev A registry someone else deployed at our salt still gets seeded.
 *
 *      The canonical CREATE2 proxy has no caller lock, so anyone can submit our salt and init code
 *      first. The deployment itself is harmless -- same creation code, same constructor argument, so
 *      the contract that lands is ours, owned by us, at their expense. What is not harmless is the
 *      script's reaction to finding it: gated on `deploymentChanged()` it would log "no changes" and
 *      exit, leaving a registry that every node reads and that holds nothing.
 *
 *      Its own contract for the reason the seed gate test is, and it front-runs by calling the proxy
 *      directly rather than by any cheatcode, so what is asserted is the real path.
 */
contract DeploySnapchainConfigRegistryFrontRunTest is DeploySnapchainConfigRegistry {
    address internal registryOwner = makeAddr("registryOwner");
    address internal deployer = makeAddr("deployer");
    address internal frontRunner = makeAddr("frontRunner");

    bytes32 internal constant SALT = bytes32(uint256(0xf00));

    function setUp() public {
        vm.createSelectFork("eth_mainnet");
    }

    function test_seedsRegistryDeployedBySomeoneElse() public {
        bytes memory initCode = bytes.concat(type(SnapchainConfigRegistry).creationCode, abi.encode(deployer));

        vm.prank(frontRunner);
        (bool success,) = CANONICAL_CREATE2_PROXY.call(abi.encodePacked(SALT, initCode));
        assertTrue(success);

        DeploySnapchainConfigRegistry.DeploymentParams memory params = DeploySnapchainConfigRegistry.DeploymentParams({
            deployer: deployer,
            owner: registryOwner,
            salts: DeploySnapchainConfigRegistry.Salts({snapchainConfigRegistry: SALT})
        });

        vm.startPrank(deployer);
        DeploySnapchainConfigRegistry.Contracts memory contracts = runDeploy(params, false);

        // The registry the front-runner deployed is the one the script was going to deploy, and the
        // script correctly declines to deploy it twice.
        assertGt(address(contracts.snapchainConfigRegistry).code.length, 0);
        assertFalse(deploymentChanged());

        runSetup(contracts, params, false);
        vm.stopPrank();

        // Seeded anyway, and owned by us throughout -- the front-runner never had a claim on it.
        SnapchainConfigRegistry deployed = contracts.snapchainConfigRegistry;
        assertEq(deployed.validatorSetCount(), 10);
        assertEq(deployed.configVersion(), 12);
        assertEq(deployed.owner(), deployer);
        assertEq(deployed.pendingOwner(), registryOwner);
    }
}
