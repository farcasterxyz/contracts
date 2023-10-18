// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import {KeyRegistryTestSuite} from "../KeyRegistry/KeyRegistryTestSuite.sol";
import {StorageRegistryTestSuite} from "../StorageRegistry/StorageRegistryTestSuite.sol";
import {KeyManager} from "../../src/KeyManager.sol";

/* solhint-disable state-visibility */

abstract contract KeyManagerTestSuite is KeyRegistryTestSuite, StorageRegistryTestSuite {
    KeyManager internal keyManager;

    function setUp() public virtual override(KeyRegistryTestSuite, StorageRegistryTestSuite) {
        super.setUp();

        keyManager = new KeyManager(address(keyRegistry), address(storageRegistry), owner, vault, 10e6);

        vm.prank(owner);
        keyRegistry.setKeyManager(address(keyManager));

        addKnownContract(address(keyManager));
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
        return _signAdd(pk, owner, keyType, key, metadataType, metadata, keyManager.nonces(owner), deadline);
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
        bytes32 digest = keyManager.hashTypedDataV4(
            keccak256(
                abi.encode(
                    keyManager.ADD_TYPEHASH(),
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
