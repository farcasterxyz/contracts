// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {
    DeployL2,
    StorageRegistry,
    IdRegistry,
    KeyRegistry,
    SignedKeyRequestValidator,
    IdManager,
    Bundler,
    RecoveryProxy,
    IBundler,
    IMetadataValidator
} from "../../script/DeployL2.s.sol";
import "forge-std/console.sol";

/* solhint-disable state-visibility */

contract DeployL2Test is DeployL2, Test {
    StorageRegistry internal storageRegistry;
    IdRegistry internal idRegistry;
    KeyRegistry internal keyRegistry;
    SignedKeyRequestValidator internal validator;
    IdManager internal idManager;
    Bundler internal bundler;
    RecoveryProxy internal recoveryProxy;

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

    address internal alpha = makeAddr("alpha");
    address internal beta = makeAddr("beta");
    address internal vault = makeAddr("vault");
    address internal relayer = makeAddr("relayer");

    // @dev OP Mainnet ETH/USD price feed
    address internal priceFeed = address(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    // @dev OP Mainnet sequencer uptime feed
    address internal uptimeFeed = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    address internal deployer = address(0x6D2b70e39C6bc63763098e336323591eb77Cd0C6);

    function setUp() public {
        vm.createSelectFork("l2_mainnet", 108869038);

        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");
        (carol, carolPk) = makeAddrAndKey("carol");
        (dave, davePk) = makeAddrAndKey("dave");
        (app, appPk) = makeAddrAndKey("app");

        DeployL2.DeploymentParams memory params = DeployL2.DeploymentParams({
            initialIdRegistryOwner: alpha,
            initialKeyRegistryOwner: alpha,
            initialBundlerOwner: alpha,
            initialValidatorOwner: alpha,
            initialRecoveryProxyOwner: alpha,
            priceFeed: priceFeed,
            uptimeFeed: uptimeFeed,
            vault: vault,
            roleAdmin: alpha,
            admin: beta,
            operator: relayer,
            treasurer: relayer,
            bundlerTrustedCaller: relayer,
            deployer: deployer,
            salts: DeployL2.Salts({
                storageRegistry: 0,
                idRegistry: 0,
                keyRegistry: 0,
                signedKeyRequestValidator: 0,
                bundler: 0,
                recoveryProxy: 0
            })
        });

        vm.startPrank(deployer);
        DeployL2.Contracts memory contracts = runDeploy(params, false);
        runSetup(contracts, params, false);
        vm.stopPrank();

        storageRegistry = contracts.storageRegistry;
        idRegistry = contracts.idRegistry;
        keyRegistry = contracts.keyRegistry;
        validator = contracts.signedKeyRequestValidator;
        bundler = contracts.bundler;
        recoveryProxy = contracts.recoveryProxy;
    }

    function test_deploymentParams() public {
        // Check deployment parameters
        assertEq(address(storageRegistry.priceFeed()), priceFeed);
        assertEq(address(storageRegistry.uptimeFeed()), uptimeFeed);
        assertEq(storageRegistry.deprecationTimestamp(), block.timestamp + 365 days);
        assertEq(storageRegistry.usdUnitPrice(), INITIAL_USD_UNIT_PRICE);
        assertEq(storageRegistry.maxUnits(), INITIAL_MAX_UNITS);
        assertEq(storageRegistry.priceFeedCacheDuration(), INITIAL_PRICE_FEED_CACHE_DURATION);
        assertEq(storageRegistry.uptimeFeedGracePeriod(), INITIAL_UPTIME_FEED_GRACE_PERIOD);

        // Role admin revoked from deployer and transferred to alpha multisig
        assertEq(storageRegistry.getRoleMemberCount(bytes32(0)), 1);
        assertEq(storageRegistry.hasRole(bytes32(0), deployer), false);
        assertEq(storageRegistry.hasRole(bytes32(0), alpha), true);

        // Owner role revoked from deployer and transferred to beta address
        assertEq(storageRegistry.getRoleMemberCount(keccak256("OWNER_ROLE")), 1);
        assertEq(storageRegistry.hasRole(keccak256("OWNER_ROLE"), deployer), false);
        assertEq(storageRegistry.hasRole(keccak256("OWNER_ROLE"), beta), true);

        // Operator role revoked from deployer, granted to relay and bundler
        assertEq(storageRegistry.getRoleMemberCount(keccak256("OPERATOR_ROLE")), 2);
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), deployer), false);
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), address(bundler)), true);
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), relayer), true);

        // Treasurer role revoked from deployer, granted to relay
        assertEq(storageRegistry.getRoleMemberCount(keccak256("TREASURER_ROLE")), 1);
        assertEq(storageRegistry.hasRole(keccak256("TREASURER_ROLE"), deployer), false);
        assertEq(storageRegistry.hasRole(keccak256("TREASURER_ROLE"), relayer), true);

        // Ownership transfers initiated from deployer to multisig
        assertEq(idRegistry.owner(), deployer);
        assertEq(idRegistry.pendingOwner(), alpha);

        assertEq(keyRegistry.owner(), deployer);
        assertEq(keyRegistry.pendingOwner(), alpha);

        // Check key registry parameters
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
        assertEq(keyRegistry.gracePeriod(), KEY_REGISTRY_MIGRATION_GRACE_PERIOD);

        // Validator owned by multisig, check deploy parameters
        assertEq(validator.owner(), alpha);
        assertEq(address(validator.idRegistry()), address(idRegistry));

        // Bundler owned by multisig, check deploy parameters
        assertEq(bundler.owner(), alpha);
        assertEq(address(bundler.idManager()), address(idManager));
        assertEq(address(bundler.storageRegistry()), address(storageRegistry));
        assertEq(address(bundler.keyRegistry()), address(keyRegistry));
        assertEq(bundler.trustedCaller(), relayer);

        // Recovery proxy owned by multisig, check deploy parameters
        assertEq(recoveryProxy.owner(), alpha);
        assertEq(address(recoveryProxy.idRegistry()), address(idRegistry));
    }

    function test_e2e() public {
        // Multisig accepts ownership transferred from deployer
        vm.startPrank(alpha);
        idRegistry.acceptOwnership();
        keyRegistry.acceptOwnership();
        vm.stopPrank();

        // Bundler trusted registers an app fid
        vm.prank(address(bundler));
        uint256 requestFid = idManager.trustedRegister(app, address(0));
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

        IBundler.SignerData[] memory signers = new IBundler.SignerData[](1);
        signers[0] = IBundler.SignerData({keyType: 1, key: key, metadataType: 1, metadata: metadata});

        // Relayer trusted registers a user fid
        vm.prank(relayer);
        bundler.trustedRegister(
            IBundler.UserData({to: alice, recovery: address(recoveryProxy), signers: signers, units: 1})
        );
        assertEq(idRegistry.idOf(alice), 2);

        // Multisig disables trusted mode
        vm.startPrank(alpha);
        idManager.disableTrustedOnly();
        keyRegistry.disableTrustedOnly();
        bundler.disableTrustedOnly();
        vm.stopPrank();

        // Carol permissionlessly registers an fid with Dave as recovery
        vm.prank(carol);
        idManager.register(dave);
        assertEq(idRegistry.idOf(carol), 3);

        // Multisig recovers Alice's FID to bob
        uint256 recoverDeadline = block.timestamp + 30;
        bytes memory recoverSig = _signTransfer(bobPk, 2, bob, recoverDeadline);
        vm.prank(alpha);
        recoveryProxy.recover(alice, bob, recoverDeadline, recoverSig);
    }

    function _signTransfer(
        uint256 pk,
        uint256 fid,
        address to,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(abi.encode(idRegistry.TRANSFER_TYPEHASH(), fid, to, idRegistry.nonces(signer), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
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
