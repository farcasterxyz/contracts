// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {
    Deploy,
    StorageRegistry,
    IdRegistry,
    KeyRegistry,
    SignedKeyRequestValidator,
    Bundler,
    IMetadataValidator
} from "../../script/Deploy.s.sol";
import "forge-std/console.sol";

/* solhint-disable state-visibility */

contract DeployTest is Deploy, Test {
    StorageRegistry internal storageRegistry;
    IdRegistry internal idRegistry;
    KeyRegistry internal keyRegistry;
    SignedKeyRequestValidator internal validator;
    Bundler internal bundler;

    address internal alice;
    uint256 internal alicePk;

    address internal bob;
    uint256 internal bobPk;

    address internal carol;
    uint256 internal carolPk;

    address internal dave;
    uint256 internal davePk;

    address internal app;
    uint256 internal appPk;

    address internal deployer = address(this);
    address internal alpha = makeAddr("alpha");
    address internal beta = makeAddr("beta");
    address internal vault = makeAddr("vault");
    address internal relayer = makeAddr("relayer");

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
        (app, appPk) = makeAddrAndKey("app");

        Deploy.DeploymentParams memory params = Deploy.DeploymentParams({
            initialIdRegistryOwner: alpha,
            initialKeyRegistryOwner: alpha,
            initialBundlerOwner: alpha,
            initialValidatorOwner: alpha,
            priceFeed: priceFeed,
            uptimeFeed: uptimeFeed,
            vault: vault,
            roleAdmin: alpha,
            admin: beta,
            operator: relayer,
            treasurer: relayer,
            bundlerTrustedCaller: relayer,
            deployer: deployer
        });

        Deploy.Contracts memory contracts = runDeploy(params, false);
        runSetup(contracts, params, false);

        storageRegistry = contracts.storageRegistry;
        idRegistry = contracts.idRegistry;
        keyRegistry = contracts.keyRegistry;
        validator = contracts.signedKeyRequestValidator;
        bundler = contracts.bundler;
    }

    function test_deploymentParams() public {
        assertEq(address(storageRegistry.priceFeed()), priceFeed);
        assertEq(address(storageRegistry.uptimeFeed()), uptimeFeed);
        assertEq(storageRegistry.deprecationTimestamp(), block.timestamp + 365 days);
        assertEq(storageRegistry.usdUnitPrice(), INITIAL_USD_UNIT_PRICE);
        assertEq(storageRegistry.maxUnits(), INITIAL_MAX_UNITS);
        assertEq(storageRegistry.priceFeedCacheDuration(), INITIAL_PRICE_FEED_CACHE_DURATION);
        assertEq(storageRegistry.uptimeFeedGracePeriod(), INITIAL_UPTIME_FEED_GRACE_PERIOD);

        assertEq(storageRegistry.getRoleMemberCount(bytes32(0)), 1);
        assertEq(storageRegistry.hasRole(bytes32(0), deployer), false);

        assertEq(storageRegistry.getRoleMemberCount(keccak256("OWNER_ROLE")), 1);
        assertEq(storageRegistry.hasRole(keccak256("OWNER_ROLE"), deployer), false);
        assertEq(storageRegistry.hasRole(keccak256("OWNER_ROLE"), beta), true);

        assertEq(storageRegistry.getRoleMemberCount(keccak256("OPERATOR_ROLE")), 2);
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), deployer), false);
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), address(bundler)), true);
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), relayer), true);

        assertEq(storageRegistry.getRoleMemberCount(keccak256("TREASURER_ROLE")), 1);
        assertEq(storageRegistry.hasRole(keccak256("TREASURER_ROLE"), deployer), false);
        assertEq(storageRegistry.hasRole(keccak256("TREASURER_ROLE"), relayer), true);

        assertEq(idRegistry.owner(), deployer);
        assertEq(idRegistry.pendingOwner(), alpha);

        assertEq(keyRegistry.owner(), deployer);
        assertEq(keyRegistry.pendingOwner(), alpha);
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
        assertEq(keyRegistry.gracePeriod(), KEY_REGISTRY_MIGRATION_GRACE_PERIOD);

        assertEq(validator.owner(), alpha);
        assertEq(address(validator.idRegistry()), address(idRegistry));

        assertEq(bundler.owner(), alpha);
        assertEq(address(bundler.idRegistry()), address(idRegistry));
        assertEq(address(bundler.storageRegistry()), address(storageRegistry));
        assertEq(address(bundler.keyRegistry()), address(keyRegistry));
        assertEq(bundler.trustedCaller(), relayer);
    }

    function test_e2e() public {
        vm.startPrank(alpha);
        idRegistry.acceptOwnership();
        keyRegistry.acceptOwnership();
        vm.stopPrank();

        vm.prank(address(bundler));
        uint256 requestFid = idRegistry.trustedRegister(app, address(0));
        uint256 deadline = block.timestamp + 60;

        bytes memory key = bytes.concat("key", bytes29(0));
        bytes memory sig = _signMetadata(appPk, requestFid, key, deadline);
        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: app,
                signature: sig,
                deadline: deadline
            })
        );

        Bundler.SignerData[] memory signers = new Bundler.SignerData[](1);
        signers[0] = Bundler.SignerData({keyType: 1, key: key, metadataType: 1, metadata: metadata});
        vm.prank(relayer);
        bundler.trustedRegister(Bundler.UserData({to: alice, recovery: bob, signers: signers, units: 1}));
        assertEq(idRegistry.idOf(alice), 2);

        vm.startPrank(alpha);
        idRegistry.disableTrustedOnly();
        keyRegistry.disableTrustedOnly();
        bundler.disableTrustedOnly();
        vm.stopPrank();

        vm.prank(carol);
        idRegistry.register(dave);
        assertEq(idRegistry.idOf(carol), 3);
    }

    function _signMetadata(
        uint256 pk,
        uint256 requestFid,
        bytes memory signerPubKey,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = validator.hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("SignedKeyRequest(uint256 requestFid,bytes key,uint256 deadline)"),
                    requestFid,
                    keccak256(signerPubKey),
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
