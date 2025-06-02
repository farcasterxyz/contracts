// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import {IdRegistryTestSuite} from "../IdRegistry/IdRegistryTestSuite.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";
import {StubValidator} from "../Utils.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";

/* solhint-disable state-visibility */

abstract contract KeyRegistryTestSuite is IdRegistryTestSuite {
    KeyRegistry internal keyRegistry;
    StubValidator internal stubValidator;

    function setUp() public virtual override {
        super.setUp();

        keyRegistry = new KeyRegistry(address(idRegistry), migrator, owner, 10);
        stubValidator = new StubValidator();

        vm.prank(owner);
        keyRegistry.unpause();

        addKnownContract(address(keyRegistry));
        addKnownContract(address(stubValidator));
    }

    function _signRemove(
        uint256 pk,
        address owner,
        bytes memory key,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = keyRegistry.hashTypedDataV4(
            keccak256(
                abi.encode(keyRegistry.REMOVE_TYPEHASH(), owner, keccak256(key), keyRegistry.nonces(owner), deadline)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }

    function _registerValidator(uint32 keyType, uint8 typeId) internal {
        _registerValidator(keyType, typeId, true);
    }

    function _registerValidator(uint32 keyType, uint8 typeId, bool isValid) internal {
        vm.prank(owner);
        keyRegistry.setValidator(keyType, typeId, IMetadataValidator(address(stubValidator)));
        stubValidator.setIsValid(isValid);
    }
}
