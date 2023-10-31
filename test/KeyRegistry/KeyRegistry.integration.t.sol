// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import {KeyRegistry, IKeyRegistry} from "../../src/KeyRegistry.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";
import {SignedKeyRequestValidator} from "../../src/validators/SignedKeyRequestValidator.sol";

import {SignedKeyRequestValidatorTestSuite} from
    "../validators/SignedKeyRequestValidator/SignedKeyRequestValidatorTestSuite.sol";
import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyRegistryIntegrationTest is KeyRegistryTestSuite, SignedKeyRequestValidatorTestSuite {
    function setUp() public override(KeyRegistryTestSuite, SignedKeyRequestValidatorTestSuite) {
        super.setUp();

        vm.prank(owner);
        keyRegistry.setValidator(1, 1, IMetadataValidator(address(validator)));
    }

    event Add(
        uint256 indexed fid,
        uint32 indexed keyType,
        bytes indexed key,
        bytes keyBytes,
        uint8 metadataType,
        bytes metadata
    );

    function testFuzzAdd(
        address to,
        uint256 signerPk,
        address recovery,
        bytes calldata _keyBytes,
        uint40 _deadline
    ) public {
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);
        address signer = vm.addr(signerPk);
        vm.assume(signer != to);

        uint256 userFid = _registerFid(to, recovery);
        uint256 requestFid = _register(signer);
        bytes memory key = _validKey(_keyBytes);

        bytes memory sig = _signMetadata(signerPk, requestFid, key, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        vm.expectEmit();
        emit Add(userFid, 1, key, key, 1, metadata);
        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, 1, key, 1, metadata);

        assertAdded(userFid, key, 1);
    }

    function testFuzzAddRevertsShortKey(
        address to,
        uint256 signerPk,
        address recovery,
        bytes calldata _keyBytes,
        uint40 _deadline,
        uint8 _shortenBy
    ) public {
        _registerFid(to, recovery);
        bytes memory key = _shortKey(_keyBytes, _shortenBy);

        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);
        address signer = vm.addr(signerPk);
        vm.assume(signer != to);

        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, requestFid, key, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.InvalidMetadata.selector);
        keyRegistry.add(to, 1, key, 1, metadata);
    }

    function testFuzzAddRevertsLongKey(
        address to,
        uint256 signerPk,
        address recovery,
        bytes calldata _keyBytes,
        uint40 _deadline,
        uint8 _lengthenBy
    ) public {
        _registerFid(to, recovery);
        bytes memory key = _longKey(_keyBytes, _lengthenBy);

        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);
        address signer = vm.addr(signerPk);
        vm.assume(signer != to);

        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, requestFid, key, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.InvalidMetadata.selector);
        keyRegistry.add(to, 1, key, 1, metadata);
    }

    function testFuzzAddRevertsInvalidSig(
        address to,
        uint256 signerPk,
        uint256 otherPk,
        address recovery,
        bytes calldata key,
        uint40 _deadline
    ) public {
        signerPk = _boundPk(signerPk);
        otherPk = _boundPk(otherPk);
        uint256 deadline = _boundDeadline(_deadline);
        vm.assume(signerPk != otherPk);
        address signer = vm.addr(signerPk);
        vm.assume(signer != to);

        _registerFid(to, recovery);
        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(otherPk, requestFid, key, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequestMetadata({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.InvalidMetadata.selector);
        keyRegistry.add(to, 1, key, 1, metadata);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        vm.prank(idRegistry.idGateway());
        return idRegistry.register(to, recovery);
    }

    function assertEq(IKeyRegistry.KeyState a, IKeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }
}
