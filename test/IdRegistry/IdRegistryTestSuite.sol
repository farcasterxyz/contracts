// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IdRegistry} from "../../src/IdRegistry.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";

/* solhint-disable state-visibility */

abstract contract IdRegistryTestSuite is TestSuiteSetup {
    IdRegistry idRegistry;

    function setUp() public virtual override {
        super.setUp();

        idRegistry = new IdRegistry(migrator, owner);

        vm.prank(owner);
        idRegistry.unpause();

        addKnownContract(address(idRegistry));
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _register(
        address caller
    ) internal returns (uint256 fid) {
        fid = _registerWithRecovery(caller, address(0));
    }

    function _registerWithRecovery(address caller, address recovery) internal returns (uint256 fid) {
        vm.prank(idRegistry.idGateway());
        fid = idRegistry.register(caller, recovery);
    }

    function _pause() public {
        vm.prank(owner);
        idRegistry.pause();
        assertEq(idRegistry.paused(), true);
    }

    function _signTransfer(
        uint256 pk,
        uint256 fid,
        address to,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(abi.encode(idRegistry.TRANSFER_TYPEHASH(), fid, to, idRegistry.nonces(signer), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }

    function _signTransferAndChangeRecovery(
        uint256 pk,
        uint256 fid,
        address to,
        address recovery,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(
                abi.encode(
                    idRegistry.TRANSFER_AND_CHANGE_RECOVERY_TYPEHASH(),
                    fid,
                    to,
                    recovery,
                    idRegistry.nonces(signer),
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }

    function _signChangeRecoveryAddress(
        uint256 pk,
        uint256 fid,
        address from,
        address to,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(
                abi.encode(
                    idRegistry.CHANGE_RECOVERY_ADDRESS_TYPEHASH(), fid, from, to, idRegistry.nonces(signer), deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }

    function _signDigest(uint256 pk, bytes32 digest) internal returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
