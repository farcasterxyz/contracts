// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry} from "../../src/IdRegistry.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";

/* solhint-disable state-visibility */

abstract contract IdRegistryTestSuite is TestSuiteSetup {
    IdRegistry idRegistry;

    function setUp() public virtual override {
        super.setUp();

        idRegistry = new IdRegistry(owner);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _register(address caller) internal returns (uint256 fid) {
        fid = _registerWithRecovery(caller, address(0));
    }

    function _registerWithRecovery(address caller, address recovery) internal returns (uint256 fid) {
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        vm.prank(caller);
        fid = idRegistry.register(recovery);
    }

    function _registerFor(uint256 callerPk, uint40 _deadline) internal {
        _registerForWithRecovery(callerPk, address(0), _deadline);
    }

    function _registerForWithRecovery(uint256 callerPk, address recovery, uint40 _deadline) internal {
        uint256 deadline = _boundDeadline(_deadline);
        callerPk = _boundPk(callerPk);

        address caller = vm.addr(callerPk);
        bytes memory sig = _signRegister(callerPk, caller, recovery, deadline);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        vm.prank(caller);
        idRegistry.registerFor(caller, recovery, deadline, sig);
    }

    function _pause() public {
        vm.prank(owner);
        idRegistry.pause();
        assertEq(idRegistry.paused(), true);
    }

    function _signRegister(
        uint256 pk,
        address to,
        address recovery,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(abi.encode(idRegistry.REGISTER_TYPEHASH(), to, recovery, idRegistry.nonces(signer), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
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

    function _signChangeRecoveryAddress(
        uint256 pk,
        uint256 fid,
        address recovery,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(
                abi.encode(
                    idRegistry.CHANGE_RECOVERY_ADDRESS_TYPEHASH(), fid, recovery, idRegistry.nonces(signer), deadline
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
