// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistryTestSuite} from "../../IdRegistry/IdRegistryTestSuite.sol";

import {SignedKeyRequestValidatorHarness} from "../../Utils.sol";

/* solhint-disable state-visibility */

abstract contract SignedKeyRequestValidatorTestSuite is IdRegistryTestSuite {
    SignedKeyRequestValidatorHarness internal validator;

    function setUp() public virtual override {
        super.setUp();

        validator = new SignedKeyRequestValidatorHarness(
            address(idRegistry),
            owner
        );
    }

    function _signMetadata(
        uint256 pk,
        uint256 requestingFid,
        bytes memory signerPubKey,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = validator.hashTypedDataV4(
            keccak256(abi.encode(validator.metadataTypehash(), requestingFid, keccak256(signerPubKey), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
