// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {StorageRegistry} from "../src/StorageRegistry.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {IdGateway} from "../src/IdGateway.sol";
import {KeyRegistry, IKeyRegistry} from "../src/KeyRegistry.sol";
import {KeyGateway} from "../src/KeyGateway.sol";
import {SignedKeyRequestValidator} from "../src/validators/SignedKeyRequestValidator.sol";
import {Bundler, IBundler} from "../src/Bundler.sol";
import {RecoveryProxy} from "../src/RecoveryProxy.sol";
import {console, ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

contract UpgradeBundler is ImmutableCreate2Deployer, Test {
    struct Salts {
        bytes32 bundler;
    }

    struct DeploymentParams {
        Salts salts;
    }

    struct Addresses {
        address storageRegistry;
        address idRegistry;
        address idGateway;
        address keyRegistry;
        address keyGateway;
        address signedKeyRequestValidator;
        address bundler;
        address recoveryProxy;
    }

    struct Contracts {
        StorageRegistry storageRegistry;
        IdRegistry idRegistry;
        IdGateway idGateway;
        KeyRegistry keyRegistry;
        KeyGateway keyGateway;
        SignedKeyRequestValidator signedKeyRequestValidator;
        Bundler bundler;
        RecoveryProxy recoveryProxy;
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

        // No changes
        addrs.storageRegistry = address(0x00000000fcCe7f938e7aE6D3c335bD6a1a7c593D);
        addrs.idRegistry = address(0x00000000Fc6c5F01Fc30151999387Bb99A9f489b);
        addrs.idGateway = payable(address(0x00000000Fc25870C6eD6b6c7E41Fb078b7656f69));
        addrs.keyRegistry = address(0x00000000Fc1237824fb747aBDE0FF18990E59b7e);
        addrs.keyGateway = address(0x00000000fC56947c7E7183f8Ca4B62398CaAdf0B);
        addrs.signedKeyRequestValidator = address(0x00000000FC700472606ED4fA22623Acf62c60553);
        addrs.recoveryProxy = address(0x00000000FcB080a4D6c39a9354dA9EB9bC104cd7);

        // Deploy new Bundler
        addrs.bundler = register(
            "Bundler", params.salts.bundler, type(Bundler).creationCode, abi.encode(addrs.idGateway, addrs.keyGateway)
        );
        deploy(broadcast);

        return Contracts({
            storageRegistry: StorageRegistry(addrs.storageRegistry),
            idRegistry: IdRegistry(addrs.idRegistry),
            idGateway: IdGateway(payable(addrs.idGateway)),
            keyRegistry: KeyRegistry(addrs.keyRegistry),
            keyGateway: KeyGateway(payable(addrs.keyGateway)),
            signedKeyRequestValidator: SignedKeyRequestValidator(addrs.signedKeyRequestValidator),
            bundler: Bundler(payable(addrs.bundler)),
            recoveryProxy: RecoveryProxy(addrs.recoveryProxy)
        });
    }

    function runSetup(Contracts memory contracts, DeploymentParams memory, bool) public {
        if (deploymentChanged()) {
            console.log("Running setup");

            // Check bundler deploy parameters
            assertEq(address(contracts.bundler.idGateway()), address(contracts.idGateway));
            assertEq(address(contracts.bundler.keyGateway()), address(contracts.keyGateway));
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
        return DeploymentParams({salts: Salts({bundler: vm.envOr("BUNDLER_CREATE2_SALT", bytes32(0))})});
    }
}
