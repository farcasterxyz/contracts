// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {IdGatewayTestSuite} from "../IdGateway/IdGatewayTestSuite.sol";

import {KeyGateway} from "../../src/KeyGateway.sol";
import {BundlerV1} from "../../src/BundlerV1.sol";

/* solhint-disable state-visibility */

abstract contract BundlerV1TestSuite is IdGatewayTestSuite {
    KeyGateway keyGateway;
    BundlerV1 bundler;

    function setUp() public virtual override {
        super.setUp();

        keyGateway = new KeyGateway(address(keyRegistry), owner);

        vm.prank(owner);
        keyRegistry.setKeyGateway(address(keyGateway));

        bundler = new BundlerV1(address(idGateway), address(keyGateway));

        addKnownContract(address(keyGateway));
        addKnownContract(address(bundler));
    }

    // Assert that a given fname was correctly registered with id 1 and recovery
    function _assertSuccessfulRegistration(address account, address recovery) internal {
        assertEq(idRegistry.idOf(account), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    // Assert that a given fname was not registered and the contracts have no registrations
    function _assertUnsuccessfulRegistration(
        address account
    ) internal {
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
