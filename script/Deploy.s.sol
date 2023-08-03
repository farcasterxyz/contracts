// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry} from "../src/IdRegistry.sol";
import {StorageRegistry} from "../src/StorageRegistry.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";
import {Bundler} from "../src/Bundler.sol";
import {ImmutableCreate2Deployer} from "./lib/ImmutableCreate2Deployer.sol";

contract Deploy is ImmutableCreate2Deployer {
    uint256 public constant INITIAL_USD_UNIT_PRICE = 5e8; // $5 USD
    uint256 public constant INITIAL_MAX_UNITS = 2_000_000;
    uint256 public constant INITIAL_PRICE_FEED_CACHE_DURATION = 1 days;
    uint256 public constant INITIAL_UPTIME_FEED_GRACE_PERIOD = 1 hours;

    uint24 public constant KEY_REGISTRY_MIGRATION_GRACE_PERIOD = 1 days;

    bytes32 internal constant STORAGE_RENT_CREATE2_SALT = bytes32(0);
    bytes32 internal constant ID_REGISTRY_CREATE2_SALT = bytes32(0);
    bytes32 internal constant KEY_REGISTRY_CREATE2_SALT = bytes32(0);
    bytes32 internal constant BUNDLER_CREATE2_SALT = bytes32(0);

    struct DeploymentParams {
        address initialIdRegistryOwner;
        address initialKeyRegistryOwner;
        address initialBundlerOwner;
        address priceFeed;
        address uptimeFeed;
        address vault;
        address roleAdmin;
        address admin;
        address operator;
        address treasurer;
        address bundlerTrustedCaller;
    }

    struct Contracts {
        StorageRegistry storageRegistry;
        IdRegistry idRegistry;
        KeyRegistry keyRegistry;
        Bundler bundler;
    }

    function run() public {
        runSetup(runDeploy(loadDeploymentParams()));
    }

    function runDeploy(DeploymentParams memory params) public returns (Contracts memory) {
        address storageRegistry = register(
            "StorageRegistry",
            STORAGE_RENT_CREATE2_SALT,
            type(StorageRegistry).creationCode,
            abi.encode(
                params.priceFeed,
                params.uptimeFeed,
                INITIAL_USD_UNIT_PRICE,
                INITIAL_MAX_UNITS,
                params.vault,
                params.roleAdmin,
                params.admin,
                params.operator,
                params.treasurer,
                INITIAL_PRICE_FEED_CACHE_DURATION,
                INITIAL_UPTIME_FEED_GRACE_PERIOD
            )
        );
        address idRegistry = register(
            "IdRegistry",
            ID_REGISTRY_CREATE2_SALT,
            type(IdRegistry).creationCode,
            abi.encode(params.initialIdRegistryOwner)
        );
        address keyRegistry = register(
            "KeyRegistry",
            KEY_REGISTRY_CREATE2_SALT,
            type(KeyRegistry).creationCode,
            abi.encode(idRegistry, KEY_REGISTRY_MIGRATION_GRACE_PERIOD, params.initialKeyRegistryOwner)
        );
        address bundler = register(
            "Bundler",
            BUNDLER_CREATE2_SALT,
            type(Bundler).creationCode,
            abi.encode(
                idRegistry, storageRegistry, keyRegistry, params.bundlerTrustedCaller, params.initialBundlerOwner
            )
        );

        deploy();

        return Contracts({
            storageRegistry: StorageRegistry(storageRegistry),
            idRegistry: IdRegistry(idRegistry),
            keyRegistry: KeyRegistry(keyRegistry),
            bundler: Bundler(payable(bundler))
        });
    }

    function runSetup(Contracts memory contracts) public {
        address bundler = address(contracts.bundler);

        vm.startBroadcast();
        contracts.idRegistry.setTrustedCaller(bundler);
        contracts.keyRegistry.setTrustedCaller(bundler);
        contracts.storageRegistry.grantRole(keccak256("OPERATOR_ROLE"), bundler);
        vm.stopBroadcast();
    }

    function loadDeploymentParams() internal view returns (DeploymentParams memory) {
        return DeploymentParams({
            initialIdRegistryOwner: vm.envAddress("ID_REGISTRY_OWNER_ADDRESS"),
            initialKeyRegistryOwner: vm.envAddress("KEY_REGISTRY_OWNER_ADDRESS"),
            initialBundlerOwner: vm.envAddress("BUNDLER_OWNER_ADDRESS"),
            priceFeed: vm.envAddress("STORAGE_RENT_PRICE_FEED_ADDRESS"),
            uptimeFeed: vm.envAddress("STORAGE_RENT_UPTIME_FEED_ADDRESS"),
            vault: vm.envAddress("STORAGE_RENT_VAULT_ADDRESS"),
            roleAdmin: vm.envAddress("STORAGE_RENT_ROLE_ADMIN_ADDRESS"),
            admin: vm.envAddress("STORAGE_RENT_ADMIN_ADDRESS"),
            operator: vm.envAddress("STORAGE_RENT_OPERATOR_ADDRESS"),
            treasurer: vm.envAddress("STORAGE_RENT_TREASURER_ADDRESS"),
            bundlerTrustedCaller: vm.envAddress("BUNDLER_TRUSTED_CALLER_ADDRESS")
        });
    }
}
