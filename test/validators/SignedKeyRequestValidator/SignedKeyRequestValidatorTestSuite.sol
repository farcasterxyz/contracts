// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IdRegistryTestSuite} from "../../IdRegistry/IdRegistryTestSuite.sol";

import {SignedKeyRequestValidator} from "../../../src/validators/SignedKeyRequestValidator.sol";

/* solhint-disable state-visibility */

abstract contract SignedKeyRequestValidatorTestSuite is IdRegistryTestSuite {
    SignedKeyRequestValidator internal validator;

    function setUp() public virtual override {
        super.setUp();

        validator = new SignedKeyRequestValidator(address(idRegistry), owner);
    }

    function _validKey(
        bytes memory keyBytes
    ) internal pure returns (bytes memory) {
        if (keyBytes.length < 32) {
            // pad with zero bytes
            bytes memory padding = new bytes(32 - keyBytes.length);
            return bytes.concat(keyBytes, padding);
        } else if (keyBytes.length > 32) {
            // truncate length
            assembly {
                mstore(keyBytes, 32)
            }
            return keyBytes;
        } else {
            return keyBytes;
        }
    }

    function _shortKey(bytes memory keyBytes, uint8 _amount) internal view returns (bytes memory) {
        uint256 amount = bound(_amount, 0, 31);
        assembly {
            mstore(keyBytes, amount)
        }
        return keyBytes;
    }

    function _longKey(bytes memory keyBytes, uint8 _amount) internal view returns (bytes memory) {
        uint256 amount = bound(_amount, 1, type(uint8).max);
        bytes memory padding = new bytes(amount);
        return bytes.concat(_validKey(keyBytes), padding);
    }

    function _signMetadata(
        uint256 pk,
        uint256 requestingFid,
        bytes memory signerPubKey,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = validator.hashTypedDataV4(
            keccak256(abi.encode(validator.METADATA_TYPEHASH(), requestingFid, keccak256(signerPubKey), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
