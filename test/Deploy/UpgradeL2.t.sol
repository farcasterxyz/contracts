// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {
    UpgradeL2,
    StorageRegistry,
    IdRegistry,
    IdGateway,
    KeyRegistry,
    KeyGateway,
    SignedKeyRequestValidator,
    Bundler,
    RecoveryProxy,
    IBundler,
    IMetadataValidator
} from "../../script/UpgradeL2.s.sol";
import "forge-std/console.sol";

/* solhint-disable state-visibility */

contract UpgradeL2Test is UpgradeL2, Test {
    StorageRegistry internal storageRegistry;
    IdRegistry internal idRegistry;
    IdGateway internal idGateway;
    KeyRegistry internal keyRegistry;
    KeyGateway internal keyGateway;
    SignedKeyRequestValidator internal validator;
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

    address internal alpha = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal beta = address(0xD84E32224A249A575A09672Da9cb58C381C4837a);
    address internal vault = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal relayer = address(0x2D93c2F74b2C4697f9ea85D0450148AA45D4D5a2);

    // @dev OP Mainnet ETH/USD price feed
    address internal priceFeed = address(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    // @dev OP Mainnet sequencer uptime feed
    address internal uptimeFeed = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    address internal deployer = address(0x6D2b70e39C6bc63763098e336323591eb77Cd0C6);

    address internal storageRegistryAddr = address(0x00000000fcCe7f938e7aE6D3c335bD6a1a7c593D);
    address internal signedKeyRequestValidatorAddr = address(0x00000000FC700472606ED4fA22623Acf62c60553);

    function setUp() public {
        vm.createSelectFork("l2_mainnet", 111079475);

        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");
        (carol, carolPk) = makeAddrAndKey("carol");
        (dave, davePk) = makeAddrAndKey("dave");
        (app, appPk) = makeAddrAndKey("app");

        vm.deal(alice, 0.5 ether);
        vm.deal(bob, 0.5 ether);
        vm.deal(carol, 0.5 ether);
        vm.deal(dave, 0.5 ether);
        vm.deal(app, 0.5 ether);

        UpgradeL2.DeploymentParams memory params = UpgradeL2.DeploymentParams({
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
            storageRegistryAddr: storageRegistryAddr,
            signedKeyRequestValidatorAddr: signedKeyRequestValidatorAddr,
            deployer: deployer,
            salts: UpgradeL2.Salts({
                storageRegistry: 0,
                idRegistry: 0,
                idGateway: 0,
                keyRegistry: 0,
                keyGateway: 0,
                signedKeyRequestValidator: 0,
                bundler: 0,
                recoveryProxy: 0
            })
        });

        vm.startPrank(deployer);
        UpgradeL2.Contracts memory contracts = runDeploy(params, false);
        runSetup(contracts, params, false);
        vm.stopPrank();

        storageRegistry = contracts.storageRegistry;
        idRegistry = contracts.idRegistry;
        idGateway = contracts.idGateway;
        keyRegistry = contracts.keyRegistry;
        keyGateway = contracts.keyGateway;
        validator = contracts.signedKeyRequestValidator;
        bundler = contracts.bundler;
        recoveryProxy = contracts.recoveryProxy;

        postDeploySetup();
    }

    function postDeploySetup() public {
        vm.prank(alpha);
        validator.setIdRegistry(address(idRegistry));
    }

    function test_deploymentParams() public {
        // Check deployment parameters
        assertEq(address(storageRegistry.priceFeed()), priceFeed);
        assertEq(address(storageRegistry.uptimeFeed()), uptimeFeed);
        assertEq(storageRegistry.deprecationTimestamp(), 1724872829);
        assertEq(storageRegistry.usdUnitPrice(), 7e8);
        assertEq(storageRegistry.maxUnits(), INITIAL_MAX_UNITS);
        assertEq(storageRegistry.priceFeedCacheDuration(), INITIAL_PRICE_FEED_CACHE_DURATION);
        assertEq(storageRegistry.uptimeFeedGracePeriod(), INITIAL_UPTIME_FEED_GRACE_PERIOD);

        // Role admin revoked from deployer and transferred to alpha multisig
        assertEq(storageRegistry.getRoleMemberCount(bytes32(0)), 1);
        assertEq(storageRegistry.hasRole(bytes32(0), deployer), false);
        assertEq(storageRegistry.hasRole(bytes32(0), alpha), true);

        // Owner role revoked from deployer and transferred to beta address
        assertEq(storageRegistry.getRoleMemberCount(keccak256("OWNER_ROLE")), 3);
        assertEq(storageRegistry.hasRole(keccak256("OWNER_ROLE"), deployer), false);
        assertEq(storageRegistry.hasRole(keccak256("OWNER_ROLE"), beta), true);

        // Operator role revoked from deployer
        assertEq(storageRegistry.getRoleMemberCount(keccak256("OPERATOR_ROLE")), 2);
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), deployer), false);

        // Operator role is not granted to new bundler, but not needed
        assertEq(storageRegistry.hasRole(keccak256("OPERATOR_ROLE"), address(bundler)), false);

        // Treasurer role revoked from deployer
        assertEq(storageRegistry.getRoleMemberCount(keccak256("TREASURER_ROLE")), 1);
        assertEq(storageRegistry.hasRole(keccak256("TREASURER_ROLE"), deployer), false);

        // Ownership transfers initiated from deployer to multisig
        assertEq(idRegistry.owner(), deployer);
        assertEq(idRegistry.pendingOwner(), alpha);

        assertEq(keyRegistry.owner(), deployer);
        assertEq(keyRegistry.pendingOwner(), alpha);

        // Check key registry parameters
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
        assertEq(address(keyRegistry.keyGateway()), address(keyGateway));
        assertEq(keyRegistry.gracePeriod(), KEY_REGISTRY_MIGRATION_GRACE_PERIOD);

        // Check ID registry parameters
        assertEq(address(idRegistry.idGateway()), address(idGateway));

        // Validator owned by multisig, check deploy parameters
        assertEq(validator.owner(), alpha);
        assertEq(address(validator.idRegistry()), address(idRegistry));

        // Bundler owned by multisig, check deploy parameters
        assertEq(bundler.owner(), alpha);
        assertEq(address(bundler.idGateway()), address(idGateway));
        assertEq(bundler.trustedCaller(), relayer);

        // Recovery proxy owned by multisig, check deploy parameters
        assertEq(recoveryProxy.owner(), alpha);
        assertEq(address(recoveryProxy.idRegistry()), address(idRegistry));
    }

    function test_e2e() public {
        // Multisig accepts ownership transferred from deployer
        vm.startPrank(alpha);
        idRegistry.acceptOwnership();
        idGateway.acceptOwnership();
        keyRegistry.acceptOwnership();
        vm.stopPrank();

        // Register an app fid
        uint256 idFee = idGateway.price();
        vm.prank(app);
        (uint256 requestFid,) = idGateway.register{value: idFee}(address(0));
        uint256 deadline = block.timestamp + 60;

        // Carol permissionlessly registers an fid with Dave as recovery
        idFee = idGateway.price();
        vm.prank(carol);
        idGateway.register{value: idFee}(dave);
        assertEq(idRegistry.idOf(carol), 2);

        // Carol permissionlessly adds a key to her fid
        bytes memory carolKey = bytes.concat("carolKey", bytes24(0));
        bytes memory carolSig = _signMetadata(appPk, requestFid, carolKey, deadline);
        bytes memory carolMetadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: app,
                signature: carolSig,
                deadline: deadline
            })
        );

        vm.prank(carol);
        keyGateway.add(1, carolKey, 1, carolMetadata);

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
