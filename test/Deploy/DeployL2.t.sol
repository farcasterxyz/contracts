// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {
    DeployL2,
    StorageRegistry,
    IdRegistry,
    IdGateway,
    KeyRegistry,
    KeyGateway,
    SignedKeyRequestValidator,
    BundlerV1,
    RecoveryProxy,
    IBundlerV1,
    IMetadataValidator
} from "../../script/DeployL2.s.sol";
import "forge-std/console.sol";

/* solhint-disable state-visibility */

contract DeployL2Test is DeployL2, Test {
    StorageRegistry internal storageRegistry;
    IdRegistry internal idRegistry;
    IdGateway internal idGateway;
    KeyRegistry internal keyRegistry;
    KeyGateway internal keyGateway;
    SignedKeyRequestValidator internal validator;
    BundlerV1 internal bundler;
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
    address internal migrator = makeAddr("migrator");

    // @dev OP Mainnet ETH/USD price feed
    address internal priceFeed = address(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    // @dev OP Mainnet sequencer uptime feed
    address internal uptimeFeed = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    address internal deployer = address(0x6D2b70e39C6bc63763098e336323591eb77Cd0C6);

    function setUp() public {
        vm.createSelectFork("op_mainnet", 108869038);

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

        DeployL2.DeploymentParams memory params = DeployL2.DeploymentParams({
            initialIdRegistryOwner: alpha,
            initialKeyRegistryOwner: alpha,
            initialValidatorOwner: alpha,
            initialRecoveryProxyOwner: alpha,
            priceFeed: priceFeed,
            uptimeFeed: uptimeFeed,
            vault: vault,
            roleAdmin: alpha,
            admin: beta,
            operator: relayer,
            treasurer: relayer,
            deployer: deployer,
            migrator: migrator,
            salts: DeployL2.Salts({
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
        DeployL2.Contracts memory contracts = runDeploy(params, false);
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

        // Ownership transfer initiated from deployer to multisig
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

        // Check bundler deploy parameters
        assertEq(address(bundler.idGateway()), address(idGateway));
        assertEq(address(bundler.keyGateway()), address(keyGateway));

        // Recovery proxy owned by multisig, check deploy parameters
        assertEq(recoveryProxy.owner(), alpha);
        assertEq(address(recoveryProxy.idRegistry()), address(idRegistry));
    }

    function test_e2e() public {
        // Multisig accepts ownership transferred from deployer
        vm.startPrank(alpha);
        idRegistry.acceptOwnership();
        idRegistry.unpause();

        keyRegistry.acceptOwnership();
        keyRegistry.unpause();

        idGateway.acceptOwnership();
        vm.stopPrank();

        // Register an app fid
        uint256 idFee = idGateway.price();
        vm.prank(app);
        (uint256 requestFid,) = idGateway.register{value: idFee}(address(0));
        uint256 deadline = block.timestamp + 60;

        // Carol registers an fid with recoveryProxy as recovery
        idFee = idGateway.price();
        vm.prank(carol);
        idGateway.register{value: idFee}(address(recoveryProxy));
        assertEq(idRegistry.idOf(carol), 2);

        // Carol adds a key to her fid
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

        // Multisig recovers Carol's FID to Bob
        uint256 recoverDeadline = block.timestamp + 30;
        bytes memory recoverSig = _signTransfer(bobPk, 2, bob, recoverDeadline);
        vm.prank(alpha);
        recoveryProxy.recover(carol, bob, recoverDeadline, recoverSig);

        // Multisig withdraws storageRegistry balance
        vm.prank(relayer);
        storageRegistry.withdraw(address(storageRegistry).balance);
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
