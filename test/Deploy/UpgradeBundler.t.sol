// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/console.sol";
import {
    UpgradeBundler,
    StorageRegistry,
    IdRegistry,
    IdGateway,
    KeyRegistry,
    IKeyRegistry,
    KeyGateway,
    SignedKeyRequestValidator,
    Bundler,
    RecoveryProxy,
    IBundler
} from "../../script/UpgradeBundler.s.sol";

/* solhint-disable state-visibility */

contract UpgradeBundlerTest is UpgradeBundler {
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

    address internal app;
    uint256 internal appPk;

    address internal alpha = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal beta = address(0xD84E32224A249A575A09672Da9cb58C381C4837a);
    address internal vault = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal relayer = address(0x2D93c2F74b2C4697f9ea85D0450148AA45D4D5a2);
    address internal migrator = relayer;

    address internal deployer = address(0x6D2b70e39C6bc63763098e336323591eb77Cd0C6);

    address internal warpcastWallet = address(0x2cd85a093261f59270804A6EA697CeA4CeBEcafE);

    function setUp() public {
        vm.createSelectFork("op_mainnet", 136433938);

        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");
        (app, appPk) = makeAddrAndKey("app");

        vm.deal(alice, 0.5 ether);
        vm.deal(bob, 0.5 ether);
        vm.deal(app, 0.5 ether);

        UpgradeBundler.DeploymentParams memory params =
            UpgradeBundler.DeploymentParams({salts: UpgradeBundler.Salts({bundler: 0})});

        vm.startPrank(deployer);
        UpgradeBundler.Contracts memory contracts = runDeploy(params, false);
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
        // Check bundler deploy parameters
        assertEq(address(bundler.idGateway()), address(idGateway));
        assertEq(address(bundler.keyGateway()), address(keyGateway));
    }

    function test_e2e() public {
        // Register an app fid
        uint256 idFee = idGateway.price();
        vm.prank(app);
        (uint256 requestFid,) = idGateway.register{value: idFee}(address(0));
        uint256 deadline = block.timestamp + 60;
        IBundler.SignerParams[] memory emptySigners = new IBundler.SignerParams[](0);

        // Register FID to alice through Bundler
        bytes memory registerSig = _signRegister(alicePk, alice, address(recoveryProxy), deadline);
        uint256 price = bundler.price(1);

        vm.prank(bob);
        uint256 fid = bundler.register{value: price}(
            IBundler.RegistrationParams({
                to: alice,
                recovery: address(recoveryProxy),
                deadline: deadline,
                sig: registerSig
            }),
            emptySigners,
            0
        );

        IBundler.SignerParams[] memory signers = new IBundler.SignerParams[](2);
        _generateKeys(signers, deadline, requestFid);

        // Register app/auth keys to Alice through bundler
        vm.prank(bob);
        bundler.addKeys(alice, signers);

        // Alice's fid is registered
        assertEq(idRegistry.idOf(alice), fid);

        // Alice's keys are registered
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 2);
        for (uint256 i; i < signers.length; i++) {
            assertEq(uint8(keyRegistry.keyDataOf(fid, signers[i].key).state), uint8(IKeyRegistry.KeyState.ADDED));
            assertEq(keyRegistry.keyDataOf(fid, signers[i].key).keyType, signers[i].keyType);
        }
    }

    function _generateKeys(IBundler.SignerParams[] memory signers, uint256 deadline, uint256 requestFid) internal {
        _generateAppKey(signers, deadline, requestFid);
        _generateAuthKey(signers, deadline, requestFid);
    }

    function _generateAppKey(IBundler.SignerParams[] memory signers, uint256 deadline, uint256 requestFid) internal {
        // Generate app key
        bytes memory appKey = bytes.concat("appKey", bytes26(0));
        bytes memory appKeySig = _signMetadata(appPk, requestFid, appKey, deadline);
        bytes memory appKeyMetadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: app,
                signature: appKeySig,
                deadline: deadline
            })
        );
        signers[0] = IBundler.SignerParams({
            keyType: 1,
            key: appKey,
            metadataType: 1,
            metadata: appKeyMetadata,
            deadline: deadline,
            sig: _signAdd(alicePk, alice, 1, appKey, 1, appKeyMetadata, deadline)
        });
    }

    function _generateAuthKey(IBundler.SignerParams[] memory signers, uint256 deadline, uint256 requestFid) internal {
        // Generate auth key
        bytes memory authKey = bytes.concat(bytes12(uint96(0)), bytes20(address(warpcastWallet)));
        bytes memory authKeySig = _signMetadata(appPk, requestFid, authKey, deadline);
        bytes memory authKeyMetadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: app,
                signature: authKeySig,
                deadline: deadline
            })
        );
        signers[1] = IBundler.SignerParams({
            keyType: 2,
            key: authKey,
            metadataType: 1,
            metadata: authKeyMetadata,
            deadline: deadline,
            sig: _signAdd(alicePk, alice, 2, authKey, 1, authKeyMetadata, keyGateway.nonces(alice) + 1, deadline)
        });
    }

    function _signRegister(
        uint256 pk,
        address to,
        address recovery,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idGateway.hashTypedDataV4(
            keccak256(abi.encode(idGateway.REGISTER_TYPEHASH(), to, recovery, idGateway.nonces(signer), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }

    function _signAdd(
        uint256 pk,
        address owner,
        uint32 keyType,
        bytes memory key,
        uint8 metadataType,
        bytes memory metadata,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        return _signAdd(pk, owner, keyType, key, metadataType, metadata, keyGateway.nonces(owner), deadline);
    }

    function _signAdd(
        uint256 pk,
        address owner,
        uint32 keyType,
        bytes memory key,
        uint8 metadataType,
        bytes memory metadata,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = keyGateway.hashTypedDataV4(
            keccak256(
                abi.encode(
                    keyGateway.ADD_TYPEHASH(),
                    owner,
                    keyType,
                    keccak256(key),
                    metadataType,
                    keccak256(metadata),
                    nonce,
                    deadline
                )
            )
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
