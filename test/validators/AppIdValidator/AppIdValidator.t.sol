// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AppIdValidator} from "../../../src/validators/AppIdValidator.sol";
import {AppIdValidatorTestSuite} from "./AppIdValidatorTestSuite.sol";

contract AppIdValidatorTest is AppIdValidatorTestSuite {
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);

    function testMetadataTypeHash() public {
        assertEq(validator.metadataTypehash(), keccak256("AppId(uint256 userFid,uint256 appFid,bytes signerPubKey)"));
    }

    /*//////////////////////////////////////////////////////////////
                              VALIDATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzValidate(uint256 signerPk, uint256 userFid, bytes calldata signerPubKey) public {
        signerPk = _boundPk(signerPk);

        address signer = vm.addr(signerPk);
        uint256 appFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, userFid, appFid, signerPubKey);

        bytes memory metadata = bytes.concat(
            abi.encodePacked(uint8(1)),
            abi.encode(AppIdValidator.AppId({appFid: appFid, appSigner: signer, signature: sig}))
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, true);
    }

    function testFuzzValidateUnownedAppFid(uint256 signerPk, uint256 userFid, bytes calldata signerPubKey) public {
        signerPk = _boundPk(signerPk);

        address signer = vm.addr(signerPk);
        uint256 appFid = _register(signer);
        uint256 unownedFid = appFid + 1;

        bytes memory sig = _signMetadata(signerPk, userFid, unownedFid, signerPubKey);

        bytes memory metadata = bytes.concat(
            abi.encodePacked(uint8(1)),
            abi.encode(AppIdValidator.AppId({appFid: unownedFid, appSigner: signer, signature: sig}))
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateWrongSigner(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        address wrongSigner
    ) public {
        signerPk = _boundPk(signerPk);

        address signer = vm.addr(signerPk);
        vm.assume(wrongSigner != signer);
        uint256 appFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, userFid, appFid, signerPubKey);

        bytes memory metadata = bytes.concat(
            abi.encodePacked(uint8(1)),
            abi.encode(AppIdValidator.AppId({appFid: appFid, appSigner: wrongSigner, signature: sig}))
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateWrongUserFid(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        uint256 wrongUserFid
    ) public {
        vm.assume(wrongUserFid != userFid);
        signerPk = _boundPk(signerPk);

        address signer = vm.addr(signerPk);
        uint256 appFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, wrongUserFid, appFid, signerPubKey);

        bytes memory metadata = bytes.concat(
            abi.encodePacked(uint8(1)),
            abi.encode(AppIdValidator.AppId({appFid: appFid, appSigner: signer, signature: sig}))
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateWrongPubKey(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        bytes calldata wrongPubKey
    ) public {
        vm.assume(keccak256(wrongPubKey) != keccak256(signerPubKey));
        signerPk = _boundPk(signerPk);

        address signer = vm.addr(signerPk);
        uint256 appFid = _register(signer);

        bytes memory sig = _signMetadata(signerPk, userFid, appFid, wrongPubKey);

        bytes memory metadata = bytes.concat(
            abi.encodePacked(uint8(1)),
            abi.encode(AppIdValidator.AppId({appFid: appFid, appSigner: signer, signature: sig}))
        );

        bool isValid = validator.validate(userFid, signerPubKey, metadata);

        assertEq(isValid, false);
    }

    function testFuzzValidateBadSig(
        uint256 signerPk,
        uint256 userFid,
        bytes calldata signerPubKey,
        bytes calldata wrongPubKey
    ) public {
        vm.assume(keccak256(wrongPubKey) != keccak256(signerPubKey));
        signerPk = _boundPk(signerPk);

        address signer = vm.addr(signerPk);
        uint256 appFid = _register(signer);

        /* generate an invalid signature */
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        bytes memory metadata = bytes.concat(
            abi.encodePacked(uint8(1)),
            abi.encode(AppIdValidator.AppId({appFid: appFid, appSigner: signer, signature: sig}))
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
