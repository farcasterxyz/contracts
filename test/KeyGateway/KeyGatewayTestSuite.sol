// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import {KeyRegistryTestSuite} from "../KeyRegistry/KeyRegistryTestSuite.sol";
import {StorageRegistryTestSuite} from "../StorageRegistry/StorageRegistryTestSuite.sol";
import {KeyGateway} from "../../src/KeyGateway.sol";

/* solhint-disable state-visibility */

abstract contract KeyGatewayTestSuite is KeyRegistryTestSuite, StorageRegistryTestSuite {
    KeyGateway internal keyGateway;

    function setUp() public virtual override(KeyRegistryTestSuite, StorageRegistryTestSuite) {
        super.setUp();

        keyGateway = new KeyGateway(address(keyRegistry), owner);

        vm.startPrank(owner);
        keyRegistry.setKeyGateway(address(keyGateway));
        vm.stopPrank();

        addKnownContract(address(keyGateway));
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
}
