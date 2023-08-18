// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {SignedKeyRequestValidator} from "../../../src/validators/SignedKeyRequestValidator.sol";
import {SignedKeyRequestValidatorTestSuite} from "./SignedKeyRequestValidatorTestSuite.sol";

contract SignedKeyRequestValidatorTest is SignedKeyRequestValidatorTestSuite {
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);

    function testMetadataTypeHash() public {
        assertEq(
            validator.metadataTypehash(), keccak256("SignedKeyRequest(uint256 requestFid,bytes key,uint256 deadline)")
        );
    }

    /*//////////////////////////////////////////////////////////////
                              VALIDATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzValidate(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        uint40 _deadline
    ) public {
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);

        address signer = vm.addr(signerPk);
        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, requestFid, signerPubKey, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, true);
    }

    function testFuzzValidateUnownedAppFid(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        uint40 _deadline
    ) public {
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);

        address signer = vm.addr(signerPk);
        uint256 requestFid = _register(signer);
        uint256 unownedFid = requestFid + 1;

        bytes memory sig = _signMetadata(signerPk, unownedFid, signerPubKey, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: unownedFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateWrongSigner(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        address wrongSigner,
        uint40 _deadline
    ) public {
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);

        address signer = vm.addr(signerPk);
        vm.assume(wrongSigner != signer);
        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, requestFid, signerPubKey, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: requestFid,
                requestSigner: wrongSigner,
                signature: sig,
                deadline: deadline
            })
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateExpired(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        uint256 wrongUserFid,
        uint40 _deadline
    ) public {
        vm.assume(wrongUserFid != userFid);
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);

        address signer = vm.addr(signerPk);
        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, requestFid, signerPubKey, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        vm.warp(deadline + 1);

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateWrongPubKey(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        bytes calldata wrongPubKey,
        uint40 _deadline
    ) public {
        vm.assume(keccak256(wrongPubKey) != keccak256(signerPubKey));
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);

        address signer = vm.addr(signerPk);
        uint256 requestFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, requestFid, wrongPubKey, deadline);

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateBadSig(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        bytes calldata wrongPubKey,
        uint40 _deadline
    ) public {
        vm.assume(keccak256(wrongPubKey) != keccak256(signerPubKey));
        signerPk = _boundPk(signerPk);
        uint256 deadline = _boundDeadline(_deadline);

        address signer = vm.addr(signerPk);
        uint256 requestFid = _register(signer);

        /* generate an invalid signature */
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        bytes memory metadata = abi.encode(
            SignedKeyRequestValidator.SignedKeyRequest({
                requestFid: requestFid,
                requestSigner: signer,
                signature: sig,
                deadline: deadline
            })
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    /*//////////////////////////////////////////////////////////////
                         SET ID REGISTRY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetIdRegistry(address caller, address idRegistry) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        validator.setIdRegistry(idRegistry);
    }

    function testFuzzSetIdRegistry(address idRegistry) public {
        address currentIdRegistry = address(validator.idRegistry());

        vm.expectEmit(false, false, false, true);
        emit SetIdRegistry(currentIdRegistry, idRegistry);

        vm.prank(owner);
        validator.setIdRegistry(idRegistry);

        assertEq(address(validator.idRegistry()), idRegistry);
    }
}
