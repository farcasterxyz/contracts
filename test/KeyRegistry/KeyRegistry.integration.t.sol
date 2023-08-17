// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {KeyRegistry} from "../../src/KeyRegistry.sol";
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
        idRegistry.disableTrustedOnly();

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

    function testFuzzAdd(address to, uint256 signerPk, address recovery, bytes calldata key, uint40 _deadline) public {
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);
        address signer = vm.addr(signerPk);

        uint256 userFid = _registerFid(to, recovery);
        uint256 requestFid = _register(signer);

        uint32 keyType = 1;
        uint8 metadataType = 1;

        bytes memory sig = _signMetadata(signerPk, requestFid, key, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        vm.expectEmit();
        emit Add(userFid, keyType, key, key, metadataType, metadata);
        vm.prank(to);
        keyRegistry.add(keyType, key, metadataType, metadata);

        assertAdded(userFid, key, keyType);
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

        _registerFid(to, recovery);
        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(otherPk, requestFid, key, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        vm.expectRevert(KeyRegistry.InvalidMetadata.selector);
        vm.prank(to);
        keyRegistry.add(1, key, 1, metadata);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        vm.prank(to);
        return idRegistry.register(recovery);
    }

    function assertEq(KeyRegistry.KeyState a, KeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }
}
