// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import {IdRegistryTestSuite} from "../IdRegistry/IdRegistryTestSuite.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";
import {KeyRegistryHarness, StubValidator} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract KeyRegistryTestSuite is IdRegistryTestSuite {
    KeyRegistryHarness internal keyRegistry;
    StubValidator internal stubValidator;

    function setUp() public virtual override {
        super.setUp();

        keyRegistry = new KeyRegistryHarness(address(idRegistry), owner);
        stubValidator = new StubValidator();

        vm.prank(owner);
        keyRegistry.setValidator(1, 1, IMetadataValidator(address(stubValidator)));
    }

    function _signAdd(
        uint256 pk,
        address owner,
        uint32 scheme,
        bytes memory key,
        bytes memory metadata,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        return _signAdd(pk, owner, scheme, key, metadata, keyRegistry.nonces(owner), deadline);
    }

    function _signAdd(
        uint256 pk,
        address owner,
        uint32 scheme,
        bytes memory key,
        bytes memory metadata,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = keyRegistry.hashTypedDataV4(
            keccak256(
                abi.encode(
                    keyRegistry.addTypehash(), owner, scheme, keccak256(key), keccak256(metadata), nonce, deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }

    function _signRemove(
        uint256 pk,
        address owner,
        bytes memory key,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = keyRegistry.hashTypedDataV4(
            keccak256(
                abi.encode(keyRegistry.removeTypehash(), owner, keccak256(key), keyRegistry.nonces(owner), deadline)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }

    function _registerValidator(uint32 scheme, uint8 typeId) internal {
        vm.prank(owner);
        keyRegistry.setValidator(scheme, typeId, IMetadataValidator(address(stubValidator)));
    }

    function _validMetadata(uint8 typeId, bytes memory fuzzedMetadata) internal pure returns (bytes memory) {
        return bytes.concat(bytes1(typeId), fuzzedMetadata);
    }
}
