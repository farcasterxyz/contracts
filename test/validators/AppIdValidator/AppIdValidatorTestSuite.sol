// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistryTestSuite} from "../../IdRegistry/IdRegistryTestSuite.sol";

import {AppIdValidatorHarness} from "../../Utils.sol";

/* solhint-disable state-visibility */

abstract contract AppIdValidatorTestSuite is IdRegistryTestSuite {
    AppIdValidatorHarness internal validator;

    function setUp() public virtual override {
        super.setUp();

        validator = new AppIdValidatorHarness(address(idRegistry), owner);
    }

    function _signMetadata(
        uint256 pk,
        uint256 userFid,
        uint256 appFid,
        bytes memory signerPubKey
    ) internal returns (bytes memory signature) {
        bytes32 digest = validator.hashTypedDataV4(
            keccak256(abi.encode(validator.metadataTypehash(), userFid, appFid, keccak256(signerPubKey)))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
