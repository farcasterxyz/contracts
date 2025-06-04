// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {
    UpgradeL2,
    StorageRegistry,
    IdRegistry,
    IIdRegistry,
    IdGateway,
    KeyRegistry,
    IKeyRegistry,
    KeyGateway,
    SignedKeyRequestValidator,
    BundlerV1,
    RecoveryProxy,
    IBundlerV1,
    IMetadataValidator
} from "../../script/UpgradeL2.s.sol";
import {
    BulkRegisterDataBuilder, BulkRegisterDefaultRecoveryDataBuilder
} from "../IdRegistry/IdRegistryTestHelpers.sol";
import {BulkAddDataBuilder, BulkResetDataBuilder} from "../KeyRegistry/KeyRegistryTestHelpers.sol";

/* solhint-disable state-visibility */

contract UpgradeL2Test is UpgradeL2 {
    using BulkRegisterDataBuilder for IIdRegistry.BulkRegisterData[];
    using BulkRegisterDefaultRecoveryDataBuilder for IIdRegistry.BulkRegisterDefaultRecoveryData[];
    using BulkAddDataBuilder for KeyRegistry.BulkAddData[];
    using BulkResetDataBuilder for KeyRegistry.BulkResetData[];

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

    address internal alpha = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal beta = address(0xD84E32224A249A575A09672Da9cb58C381C4837a);
    address internal vault = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal relayer = address(0x2D93c2F74b2C4697f9ea85D0450148AA45D4D5a2);
    address internal migrator = relayer;

    // @dev OP Mainnet ETH/USD price feed
    address internal priceFeed = address(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    // @dev OP Mainnet sequencer uptime feed
    address internal uptimeFeed = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    address internal deployer = address(0x6D2b70e39C6bc63763098e336323591eb77Cd0C6);

    address internal storageRegistryAddr = address(0x00000000fcCe7f938e7aE6D3c335bD6a1a7c593D);
    address internal signedKeyRequestValidatorAddr = address(0x00000000FC700472606ED4fA22623Acf62c60553);

    function setUp() public {
        vm.createSelectFork("op_mainnet", 111079475);

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
            initialValidatorOwner: alpha,
            initialRecoveryProxyOwner: alpha,
            storageRegistryAddr: storageRegistryAddr,
            signedKeyRequestValidatorAddr: signedKeyRequestValidatorAddr,
            deployer: deployer,
            migrator: migrator,
            salts: UpgradeL2.Salts({
                idRegistry: 0,
                idGateway: 0,
                keyRegistry: 0,
                keyGateway: 0,
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

        // Ownership transfer initiated from deployer to multisig
        assertEq(idRegistry.owner(), deployer);
        assertEq(idRegistry.pendingOwner(), alpha);
        assertEq(keyRegistry.owner(), deployer);
        assertEq(keyRegistry.pendingOwner(), alpha);

        // Check key registry parameters
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
        assertEq(address(keyRegistry.keyGateway()), address(keyGateway));
        assertEq(keyRegistry.gracePeriod(), KEY_REGISTRY_MIGRATION_GRACE_PERIOD);
        assertEq(address(keyRegistry.migrator()), migrator);
        assertEq(keyRegistry.paused(), true);

        // Check key gateway parameters
        assertEq(address(keyGateway.keyRegistry()), address(keyRegistry));
        assertEq(address(keyGateway.owner()), address(alpha));

        // Check ID registry parameters
        assertEq(address(idRegistry.idGateway()), address(idGateway));
        assertEq(address(idRegistry.migrator()), migrator);
        assertEq(idRegistry.paused(), true);

        // Check ID gateway parameters
        assertEq(address(idGateway.idRegistry()), address(idRegistry));
        assertEq(address(idGateway.storageRegistry()), address(storageRegistry));
        assertEq(address(idGateway.owner()), address(alpha));

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
        // ID Registry is paused
        vm.prank(carol);
        vm.expectRevert("Pausable: paused");
        idGateway.register{value: 0.1 ether}(address(recoveryProxy));

        // Key Registry is paused
        vm.prank(carol);
        vm.expectRevert("Pausable: paused");
        keyGateway.add(1, "key", 1, "metadata");

        // Multisig accepts ownership transferred from deployer
        vm.startPrank(alpha);
        idRegistry.acceptOwnership();
        keyRegistry.acceptOwnership();
        vm.stopPrank();

        // Set up and perform migration
        IdRegistry.BulkRegisterData[] memory customRecoveryFids =
            BulkRegisterDataBuilder.empty().addFid(2).addFid(3).addFid(5).addFid(9).addFid(10);
        IdRegistry.BulkRegisterDefaultRecoveryData[] memory defaultRecoveryFids =
            BulkRegisterDefaultRecoveryDataBuilder.empty().addFid(1).addFid(4).addFid(6).addFid(7).addFid(8);

        IKeyRegistry.BulkAddData[] memory migratedKeys = BulkAddDataBuilder.empty().addFid(1).addKey(
            0, "key1", "metadata1"
        ).addFid(2).addKey(1, "key2", "metadata2").addFid(3).addKey(2, "key3", "metadata3").addKey(
            2, "key4", "metadata4"
        ).addFid(4).addKey(3, "key5", "metadata5").addFid(5).addKey(4, "key6", "metadata6").addKey(
            4, "key7", "metadata7"
        ).addKey(4, "key8", "metadata8");

        vm.startPrank(migrator);
        idRegistry.bulkRegisterIds(customRecoveryFids);
        idRegistry.bulkRegisterIdsWithDefaultRecovery(defaultRecoveryFids, address(recoveryProxy));
        idRegistry.setIdCounter(10);
        idRegistry.migrate();

        keyRegistry.bulkAddKeysForMigration(migratedKeys);
        keyRegistry.migrate();
        vm.stopPrank();

        // Verify post-migration state
        assertEq(idRegistry.isMigrated(), true);
        assertEq(keyRegistry.isMigrated(), true);

        assertEq(idRegistry.custodyOf(1), BulkRegisterDataBuilder.custodyOf(1));
        assertEq(idRegistry.custodyOf(2), BulkRegisterDataBuilder.custodyOf(2));
        assertEq(idRegistry.custodyOf(3), BulkRegisterDataBuilder.custodyOf(3));
        assertEq(idRegistry.custodyOf(4), BulkRegisterDataBuilder.custodyOf(4));
        assertEq(idRegistry.custodyOf(5), BulkRegisterDataBuilder.custodyOf(5));
        assertEq(idRegistry.custodyOf(6), BulkRegisterDataBuilder.custodyOf(6));
        assertEq(idRegistry.custodyOf(7), BulkRegisterDataBuilder.custodyOf(7));
        assertEq(idRegistry.custodyOf(8), BulkRegisterDataBuilder.custodyOf(8));
        assertEq(idRegistry.custodyOf(9), BulkRegisterDataBuilder.custodyOf(9));
        assertEq(idRegistry.custodyOf(10), BulkRegisterDataBuilder.custodyOf(10));

        assertEq(idRegistry.recoveryOf(2), BulkRegisterDataBuilder.recoveryOf(2));
        assertEq(idRegistry.recoveryOf(3), BulkRegisterDataBuilder.recoveryOf(3));
        assertEq(idRegistry.recoveryOf(5), BulkRegisterDataBuilder.recoveryOf(5));
        assertEq(idRegistry.recoveryOf(9), BulkRegisterDataBuilder.recoveryOf(9));
        assertEq(idRegistry.recoveryOf(10), BulkRegisterDataBuilder.recoveryOf(10));

        assertEq(idRegistry.recoveryOf(1), address(recoveryProxy));
        assertEq(idRegistry.recoveryOf(4), address(recoveryProxy));
        assertEq(idRegistry.recoveryOf(6), address(recoveryProxy));
        assertEq(idRegistry.recoveryOf(7), address(recoveryProxy));
        assertEq(idRegistry.recoveryOf(8), address(recoveryProxy));

        assertEq(keyRegistry.totalKeys(1, IKeyRegistry.KeyState.ADDED), 1);
        assertEq(keyRegistry.totalKeys(2, IKeyRegistry.KeyState.ADDED), 1);
        assertEq(keyRegistry.totalKeys(3, IKeyRegistry.KeyState.ADDED), 2);
        assertEq(keyRegistry.totalKeys(4, IKeyRegistry.KeyState.ADDED), 1);
        assertEq(keyRegistry.totalKeys(5, IKeyRegistry.KeyState.ADDED), 3);

        assertEq(keyRegistry.keyAt(1, IKeyRegistry.KeyState.ADDED, 0), "key1");
        assertEq(keyRegistry.keyAt(2, IKeyRegistry.KeyState.ADDED, 0), "key2");
        assertEq(keyRegistry.keyAt(3, IKeyRegistry.KeyState.ADDED, 0), "key3");
        assertEq(keyRegistry.keyAt(3, IKeyRegistry.KeyState.ADDED, 1), "key4");
        assertEq(keyRegistry.keyAt(4, IKeyRegistry.KeyState.ADDED, 0), "key5");
        assertEq(keyRegistry.keyAt(5, IKeyRegistry.KeyState.ADDED, 0), "key6");
        assertEq(keyRegistry.keyAt(5, IKeyRegistry.KeyState.ADDED, 1), "key7");
        assertEq(keyRegistry.keyAt(5, IKeyRegistry.KeyState.ADDED, 2), "key8");

        // Multisig unpauses registries
        vm.startPrank(alpha);
        idRegistry.unpause();
        keyRegistry.unpause();
        vm.stopPrank();

        // Register an app fid
        uint256 idFee = idGateway.price();
        vm.prank(app);
        (uint256 requestFid,) = idGateway.register{value: idFee}(address(0));
        uint256 deadline = block.timestamp + 60;
        assertEq(requestFid, 11);
        assertEq(idRegistry.idOf(app), 11);

        // Carol permissionlessly registers an fid with recoveryProxy as recovery
        idFee = idGateway.price();
        vm.prank(carol);
        idGateway.register{value: idFee}(address(recoveryProxy));
        assertEq(idRegistry.idOf(carol), 12);

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

        // Multisig recovers Carol's FID to Bob
        uint256 recoverDeadline = block.timestamp + 30;
        bytes memory recoverSig = _signTransfer(bobPk, 12, bob, recoverDeadline);
        vm.prank(alpha);
        recoveryProxy.recover(carol, bob, recoverDeadline, recoverSig);
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
