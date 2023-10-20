// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {IdManagerTestSuite} from "../IdManager/IdManagerTestSuite.sol";

import {KeyManager} from "../../src/KeyManager.sol";
import {Bundler} from "../../src/Bundler.sol";

/* solhint-disable state-visibility */

abstract contract BundlerTestSuite is IdManagerTestSuite {
    KeyManager keyManager;
    Bundler bundler;

    function setUp() public virtual override {
        super.setUp();

        keyManager = new KeyManager(address(keyRegistry), address(storageRegistry), owner, vault, 10e6);

        vm.prank(owner);
        keyRegistry.setKeyManager(address(keyManager));

        // Set up the BundleRegistry
        bundler = new Bundler(
            address(idManager),
            address(keyManager),
            address(storageRegistry),
            address(this),
            owner
        );
    }

    // Assert that a given fname was correctly registered with id 1 and recovery
    function _assertSuccessfulRegistration(address account, address recovery) internal {
        assertEq(idRegistry.idOf(account), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    // Assert that a given fname was not registered and the contracts have no registrations
    function _assertUnsuccessfulRegistration(address account) internal {
        assertEq(idRegistry.idOf(account), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
