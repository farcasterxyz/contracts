// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {Deploy, StorageRent, IdRegistry, KeyRegistry, Bundler} from "../../script/Deploy.s.sol";

/* solhint-disable state-visibility */

contract DeployTest is Test {
    Deploy internal deploy;
    StorageRent internal storageRent;
    IdRegistry internal idRegistry;
    KeyRegistry internal keyRegistry;
    Bundler internal bundler;

    address internal alice;
    uint256 internal alicePk;

    address internal bob;
    uint256 internal bobPk;

    address internal carol;
    uint256 internal carolPk;

    address internal dave;
    uint256 internal davePk;

    address internal owner = makeAddr("owner");
    address internal vault = makeAddr("vault");
    address internal roleAdmin = makeAddr("roleAdmin");
    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal treasurer = makeAddr("treasurer");
    address internal bundlerTrustedCaller = makeAddr("bundlerTrustedCaller");

    address internal priceFeed = address(0x57241A37733983F97C4Ab06448F244A1E0Ca0ba8);
    address internal uptimeFeed = address(0x4C4814aa04433e0FB31310379a4D6946D5e1D353);

    function setUp() public {
        vm.createSelectFork("testnet");

        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");
        (carol, carolPk) = makeAddrAndKey("carol");
        (dave, davePk) = makeAddrAndKey("dave");

        Deploy.DeploymentParams memory params = Deploy.DeploymentParams({
            initialIdRegistryOwner: owner,
            initialKeyRegistryOwner: owner,
            initialBundlerOwner: owner,
            priceFeed: priceFeed,
            uptimeFeed: uptimeFeed,
            vault: vault,
            roleAdmin: roleAdmin,
            admin: admin,
            operator: operator,
            treasurer: treasurer,
            bundlerTrustedCaller: bundlerTrustedCaller
        });

        deploy = new Deploy();

        Deploy.Contracts memory contracts = deploy.runDeploy(params);

        storageRent = contracts.storageRent;
        idRegistry = contracts.idRegistry;
        keyRegistry = contracts.keyRegistry;
        bundler = contracts.bundler;
    }

    function test_deploymentParams() public {
        assertEq(address(storageRent.priceFeed()), priceFeed);
        assertEq(address(storageRent.uptimeFeed()), uptimeFeed);
        assertEq(storageRent.deprecationTimestamp(), block.timestamp + deploy.INITIAL_RENTAL_PERIOD());
        assertEq(storageRent.usdUnitPrice(), deploy.INITIAL_USD_UNIT_PRICE());
        assertEq(storageRent.maxUnits(), deploy.INITIAL_MAX_UNITS());
        assertEq(storageRent.priceFeedCacheDuration(), deploy.INITIAL_PRICE_FEED_CACHE_DURATION());
        assertEq(storageRent.uptimeFeedGracePeriod(), deploy.INITIAL_UPTIME_FEED_GRACE_PERIOD());

        assertEq(idRegistry.owner(), owner);

        assertEq(keyRegistry.owner(), owner);
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
        assertEq(keyRegistry.gracePeriod(), deploy.KEY_REGISTRY_MIGRATION_GRACE_PERIOD());

        assertEq(bundler.owner(), owner);
        assertEq(address(bundler.idRegistry()), address(idRegistry));
        assertEq(address(bundler.storageRent()), address(storageRent));
        assertEq(address(bundler.keyRegistry()), address(keyRegistry));
        assertEq(bundler.trustedCaller(), bundlerTrustedCaller);
    }

    function test_e2e() public {
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        vm.prank(roleAdmin);
        storageRent.grantRole(keccak256("OPERATOR_ROLE"), address(bundler));

        vm.prank(bundlerTrustedCaller);
        bundler.trustedRegister(alice, bob, 0, "key", "metadata", 1);
        assertEq(idRegistry.idOf(alice), 1);

        vm.startPrank(owner);
        idRegistry.disableTrustedOnly();
        keyRegistry.disableTrustedOnly();
        bundler.disableTrustedOnly();
        vm.stopPrank();

        vm.prank(carol);
        idRegistry.register(dave);
        assertEq(idRegistry.idOf(carol), 2);
    }
}
