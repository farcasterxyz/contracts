// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry} from "../src/IdRegistry.sol";
import {StorageRegistry} from "../src/StorageRegistry.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";
import {SignedKeyRequestValidator} from "../src/validators/SignedKeyRequestValidator.sol";
import {Bundler, IBundler} from "../src/Bundler.sol";
import {RecoveryProxy} from "../src/RecoveryProxy.sol";
import {IMetadataValidator} from "../src/interfaces/IMetadataValidator.sol";
import {console, ImmutableCreate2Deployer} from "./lib/ImmutableCreate2Deployer.sol";

contract DeployL2 is ImmutableCreate2Deployer {
    uint256 public constant INITIAL_USD_UNIT_PRICE = 5e8; // $5 USD
    uint256 public constant INITIAL_MAX_UNITS = 200_000;
    uint256 public constant INITIAL_PRICE_FEED_CACHE_DURATION = 1 days;
    uint256 public constant INITIAL_UPTIME_FEED_GRACE_PERIOD = 1 hours;

    uint24 public constant KEY_REGISTRY_MIGRATION_GRACE_PERIOD = 1 days;

    struct Salts {
        bytes32 storageRegistry;
        bytes32 idRegistry;
        bytes32 keyRegistry;
        bytes32 signedKeyRequestValidator;
        bytes32 bundler;
        bytes32 recoveryProxy;
    }

    struct DeploymentParams {
        address initialIdRegistryOwner;
        address initialKeyRegistryOwner;
        address initialBundlerOwner;
        address initialValidatorOwner;
        address initialRecoveryProxyOwner;
        address priceFeed;
        address uptimeFeed;
        address vault;
        address roleAdmin;
        address admin;
        address operator;
        address treasurer;
        address bundlerTrustedCaller;
        address deployer;
        Salts salts;
    }

    struct Contracts {
        StorageRegistry storageRegistry;
        IdRegistry idRegistry;
        KeyRegistry keyRegistry;
        SignedKeyRequestValidator signedKeyRequestValidator;
        Bundler bundler;
        RecoveryProxy recoveryProxy;
    }

    function run() public {
        runSetup(runDeploy(loadDeploymentParams()));
    }

    function runDeploy(DeploymentParams memory params) public returns (Contracts memory) {
        return runDeploy(params, true);
    }

    function runDeploy(DeploymentParams memory params, bool broadcast) public returns (Contracts memory) {
        address storageRegistry = register(
            "StorageRegistry",
            params.salts.storageRegistry,
            type(StorageRegistry).creationCode,
            abi.encode(
                params.priceFeed,
                params.uptimeFeed,
                INITIAL_USD_UNIT_PRICE,
                INITIAL_MAX_UNITS,
                params.vault,
                params.deployer,
                params.admin,
                params.operator,
                params.treasurer
            )
        );
        address idRegistry =
            register("IdRegistry", params.salts.idRegistry, type(IdRegistry).creationCode, abi.encode(params.deployer));
        address keyRegistry = register(
            "KeyRegistry",
            params.salts.keyRegistry,
            type(KeyRegistry).creationCode,
            abi.encode(idRegistry, params.deployer)
        );
        address signedKeyRequestValidator = register(
            "SignedKeyRequestValidator",
            params.salts.signedKeyRequestValidator,
            type(SignedKeyRequestValidator).creationCode,
            abi.encode(idRegistry, params.initialValidatorOwner)
        );
        address bundler = register(
            "Bundler",
            params.salts.bundler,
            type(Bundler).creationCode,
            abi.encode(
                idRegistry, storageRegistry, keyRegistry, params.bundlerTrustedCaller, params.initialBundlerOwner
            )
        );
        address recoveryProxy = register(
            "RecoveryProxy",
            params.salts.recoveryProxy,
            type(RecoveryProxy).creationCode,
            abi.encode(idRegistry, params.initialRecoveryProxyOwner)
        );

        deploy(broadcast);

        return Contracts({
            storageRegistry: StorageRegistry(storageRegistry),
            idRegistry: IdRegistry(idRegistry),
            keyRegistry: KeyRegistry(keyRegistry),
            signedKeyRequestValidator: SignedKeyRequestValidator(signedKeyRequestValidator),
            bundler: Bundler(payable(bundler)),
            recoveryProxy: RecoveryProxy(recoveryProxy)
        });
    }

    function runSetup(Contracts memory contracts, DeploymentParams memory params, bool broadcast) public {
        if (deploymentChanged()) {
            console.log("Running setup");
            address bundler = address(contracts.bundler);

            if (broadcast) vm.startBroadcast();
            contracts.idRegistry.setTrustedCaller(bundler);
            contracts.idRegistry.transferOwnership(params.initialIdRegistryOwner);

            contracts.keyRegistry.setTrustedCaller(bundler);
            contracts.keyRegistry.setValidator(1, 1, IMetadataValidator(address(contracts.signedKeyRequestValidator)));
            contracts.keyRegistry.transferOwnership(params.initialKeyRegistryOwner);

            contracts.storageRegistry.grantRole(keccak256("OPERATOR_ROLE"), bundler);
            contracts.storageRegistry.grantRole(0x00, params.roleAdmin);
            contracts.storageRegistry.renounceRole(0x00, params.deployer);
            if (broadcast) vm.stopBroadcast();
        } else {
            console.log("No changes, skipping setup");
        }
    }

    function runSetup(Contracts memory contracts) public {
        DeploymentParams memory params = loadDeploymentParams();
        runSetup(contracts, params, true);
    }

    function loadDeploymentParams() internal returns (DeploymentParams memory) {
        return DeploymentParams({
            initialIdRegistryOwner: vm.envAddress("ID_REGISTRY_OWNER_ADDRESS"),
            initialKeyRegistryOwner: vm.envAddress("KEY_REGISTRY_OWNER_ADDRESS"),
            initialBundlerOwner: vm.envAddress("BUNDLER_OWNER_ADDRESS"),
            initialValidatorOwner: vm.envAddress("METADATA_VALIDATOR_OWNER_ADDRESS"),
            initialRecoveryProxyOwner: vm.envAddress("RECOVERY_PROXY_OWNER_ADDRESS"),
            priceFeed: vm.envAddress("STORAGE_RENT_PRICE_FEED_ADDRESS"),
            uptimeFeed: vm.envAddress("STORAGE_RENT_UPTIME_FEED_ADDRESS"),
            vault: vm.envAddress("STORAGE_RENT_VAULT_ADDRESS"),
            roleAdmin: vm.envAddress("STORAGE_RENT_ROLE_ADMIN_ADDRESS"),
            admin: vm.envAddress("STORAGE_RENT_ADMIN_ADDRESS"),
            operator: vm.envAddress("STORAGE_RENT_OPERATOR_ADDRESS"),
            treasurer: vm.envAddress("STORAGE_RENT_TREASURER_ADDRESS"),
            bundlerTrustedCaller: vm.envAddress("BUNDLER_TRUSTED_CALLER_ADDRESS"),
            deployer: vm.envAddress("DEPLOYER"),
            salts: Salts({
                storageRegistry: vm.envOr("STORAGE_RENT_CREATE2_SALT", bytes32(0)),
                idRegistry: vm.envOr("ID_REGISTRY_CREATE2_SALT", bytes32(0)),
                keyRegistry: vm.envOr("KEY_REGISTRY_CREATE2_SALT", bytes32(0)),
                signedKeyRequestValidator: vm.envOr("SIGNED_KEY_REQUEST_VALIDATOR_CREATE2_SALT", bytes32(0)),
                bundler: vm.envOr("BUNDLER_CREATE2_SALT", bytes32(0)),
                recoveryProxy: vm.envOr("RECOVERY_PROXY_CREATE2_SALT", bytes32(0))
            })
        });
    }
}
