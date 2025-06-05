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

/* solhint-disable state-visibility */

contract AuthKeysTest is Test {
    StorageRegistry internal storageRegistry = StorageRegistry(0x00000000fcCe7f938e7aE6D3c335bD6a1a7c593D);
    IdRegistry internal idRegistry = IdRegistry(0x00000000Fc6c5F01Fc30151999387Bb99A9f489b);
    IdGateway internal idGateway = IdGateway(payable(0x00000000Fc25870C6eD6b6c7E41Fb078b7656f69));
    KeyRegistry internal keyRegistry = KeyRegistry(0x00000000Fc1237824fb747aBDE0FF18990E59b7e);
    KeyGateway internal keyGateway = KeyGateway(0x00000000fC56947c7E7183f8Ca4B62398CaAdf0B);
    SignedKeyRequestValidator internal validator = SignedKeyRequestValidator(0x00000000FC700472606ED4fA22623Acf62c60553);
    BundlerV1 internal bundler = BundlerV1(payable(0x00000000FC04c910A0b5feA33b03E0447AD0B0aA));
    RecoveryProxy internal recoveryProxy = RecoveryProxy(0x00000000FcB080a4D6c39a9354dA9EB9bC104cd7);

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

    address internal horsefacts = address(0x2cd85a093261f59270804A6EA697CeA4CeBEcafE);
    address internal warpcastWallet = address(0x2cd85a093261f59270804A6EA697CeA4CeBEcafE);

    address internal invalid;

    address internal alpha = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal beta = address(0xD84E32224A249A575A09672Da9cb58C381C4837a);
    address internal vault = address(0x53c6dA835c777AD11159198FBe11f95E5eE6B692);
    address internal relayer = address(0x2D93c2F74b2C4697f9ea85D0450148AA45D4D5a2);
    address internal migrator = relayer;

    function setUp() public {
        vm.createSelectFork("op_mainnet", 134877573);

        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");
        (carol, carolPk) = makeAddrAndKey("carol");
        (dave, davePk) = makeAddrAndKey("dave");
        (app, appPk) = makeAddrAndKey("app");

        invalid = makeAddr("invalid");

        vm.deal(alice, 0.5 ether);
        vm.deal(bob, 0.5 ether);
        vm.deal(carol, 0.5 ether);
        vm.deal(dave, 0.5 ether);
        vm.deal(app, 0.5 ether);
    }

    function test_e2e() public {
        // Register an app fid
        uint256 idFee = idGateway.price();
        vm.prank(app);
        (uint256 requestFid,) = idGateway.register{value: idFee}(address(0));
        uint256 deadline = block.timestamp + 60;

        // Enable auth keys
        vm.prank(alpha);
        keyRegistry.setValidator(2, 1, IMetadataValidator(address(validator)));

        // Register auth key with index 0
        bytes memory authKey = bytes.concat(bytes12(uint96(0)), bytes20(address(warpcastWallet)));
        bytes memory sig = _signMetadata(appPk, requestFid, authKey, deadline);
        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: app,
                signature: sig,
                deadline: deadline
            })
        );

        vm.startPrank(horsefacts);
        keyGateway.add(2, authKey, 1, metadata);

        IKeyRegistry.KeyData memory keyData = keyRegistry.keyDataOf(3621, authKey);
        assertEq(keyData.keyType, 2);
        assertEq(uint8(keyData.state), uint8(IKeyRegistry.KeyState.ADDED));

        bytes memory invalidAuthKey = abi.encode(invalid);
        IKeyRegistry.KeyData memory invalidKeyData = keyRegistry.keyDataOf(3621, invalidAuthKey);

        assertEq(invalidKeyData.keyType, 0);
        assertEq(uint8(invalidKeyData.state), uint8(IKeyRegistry.KeyState.NULL));

        // Register a new app key
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

        keyGateway.add(1, appKey, 1, appKeyMetadata);

        // Revoke auth key
        keyRegistry.remove(authKey);

        keyData = keyRegistry.keyDataOf(3621, authKey);
        assertEq(keyData.keyType, 2);
        assertEq(uint8(keyData.state), uint8(IKeyRegistry.KeyState.REMOVED));

        // Auth key is permanently revoked
        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyGateway.add(2, authKey, 1, metadata);

        // Revoke new app key
        keyRegistry.remove(appKey);

        // App key is permanently revoked
        keyData = keyRegistry.keyDataOf(3621, appKey);
        assertEq(keyData.keyType, 1);
        assertEq(uint8(keyData.state), uint8(IKeyRegistry.KeyState.REMOVED));

        // Register new auth key with index 1
        bytes memory authKeyIdx1 = bytes.concat(bytes12(uint96(1)), bytes20(address(warpcastWallet)));
        bytes memory sigIdx1 = _signMetadata(appPk, requestFid, authKeyIdx1, deadline);
        bytes memory metadataIdx1 = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: app,
                signature: sigIdx1,
                deadline: deadline
            })
        );

        keyGateway.add(2, authKeyIdx1, 1, metadataIdx1);
        keyData = keyRegistry.keyDataOf(3621, authKeyIdx1);
        assertEq(keyData.keyType, 2);
        assertEq(uint8(keyData.state), uint8(IKeyRegistry.KeyState.ADDED));

        vm.stopPrank();
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
