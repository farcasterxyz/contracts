// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IdRegistryHarness} from "../Utils.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";

/* solhint-disable state-visibility */

abstract contract IdRegistryTestSuite is TestSuiteSetup {
    IdRegistryHarness idRegistry;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);

    uint256 constant SECP_256K1_ORDER = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    function setUp() public virtual override {
        super.setUp();

        idRegistry = new IdRegistryHarness(FORWARDER);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _register(address caller) internal returns (uint256 fid) {
        fid = _registerWithRecovery(caller, address(0));
    }

    function _registerWithRecovery(address caller, address recovery) internal returns (uint256 fid) {
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

        idRegistry.disableTrustedOnly();
        vm.prank(caller);
        idRegistry.registerFor(caller, recovery, deadline, sig);
    }

    function _pauseRegistrations() public {
        vm.prank(owner);
        idRegistry.pauseRegistration();
        assertEq(idRegistry.paused(), true);
    }

    function _boundPk(uint256 pk) internal view returns (uint256) {
        return bound(pk, 1, SECP_256K1_ORDER - 1);
    }

    function _boundDeadline(uint40 deadline) internal view returns (uint256) {
        return block.timestamp + uint256(bound(deadline, 1, type(uint40).max));
    }

    function _signRegister(
        uint256 pk,
        address to,
        address recovery,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(abi.encode(idRegistry.registerTypehash(), to, recovery, idRegistry.nonces(to), deadline))
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
        bytes32 digest = idRegistry.hashTypedDataV4(
            keccak256(abi.encode(idRegistry.transferTypehash(), fid, to, idRegistry.nonces(to), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
