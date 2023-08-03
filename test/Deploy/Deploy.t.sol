// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {Deploy, StorageRegistry, IdRegistry, KeyRegistry, Bundler} from "../../script/Deploy.s.sol";

/* solhint-disable state-visibility */

contract DeployTest is Test {
    Deploy internal deploy;
    StorageRegistry internal storageRegistry;
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

    // @dev OP Mainnet ETH/USD price feed
    address internal priceFeed = address(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    // @dev OP Mainnet sequencer uptime feed
    address internal uptimeFeed = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    function setUp() public {
        vm.createSelectFork("mainnet");

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

        storageRegistry = contracts.storageRegistry;
        idRegistry = contracts.idRegistry;
        keyRegistry = contracts.keyRegistry;
        bundler = contracts.bundler;
    }

    function test_deploymentParams() public {
        assertEq(address(storageRegistry.priceFeed()), priceFeed);
        assertEq(address(storageRegistry.uptimeFeed()), uptimeFeed);
        assertEq(storageRegistry.deprecationTimestamp(), block.timestamp + 365 days);
        assertEq(storageRegistry.usdUnitPrice(), deploy.INITIAL_USD_UNIT_PRICE());
        assertEq(storageRegistry.maxUnits(), deploy.INITIAL_MAX_UNITS());
        assertEq(storageRegistry.priceFeedCacheDuration(), deploy.INITIAL_PRICE_FEED_CACHE_DURATION());
        assertEq(storageRegistry.uptimeFeedGracePeriod(), deploy.INITIAL_UPTIME_FEED_GRACE_PERIOD());

        assertEq(idRegistry.owner(), owner);

        assertEq(keyRegistry.owner(), owner);
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
        assertEq(keyRegistry.gracePeriod(), deploy.KEY_REGISTRY_MIGRATION_GRACE_PERIOD());

        assertEq(bundler.owner(), owner);
        assertEq(address(bundler.idRegistry()), address(idRegistry));
        assertEq(address(bundler.storageRegistry()), address(storageRegistry));
        assertEq(address(bundler.keyRegistry()), address(keyRegistry));
        assertEq(bundler.trustedCaller(), bundlerTrustedCaller);
    }

    function test_e2e() public {
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        vm.prank(roleAdmin);
        storageRegistry.grantRole(keccak256("OPERATOR_ROLE"), address(bundler));

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
