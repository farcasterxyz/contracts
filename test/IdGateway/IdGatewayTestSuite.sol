// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {StorageRegistryTestSuite} from "../StorageRegistry/StorageRegistryTestSuite.sol";
import {IdRegistryTestSuite} from "../IdRegistry/IdRegistryTestSuite.sol";
import {KeyRegistryTestSuite} from "../KeyRegistry/KeyRegistryTestSuite.sol";

import {IdGateway} from "../../src/IdGateway.sol";

/* solhint-disable state-visibility */

abstract contract IdGatewayTestSuite is StorageRegistryTestSuite, KeyRegistryTestSuite {
    IdGateway idGateway;

    function setUp() public virtual override(StorageRegistryTestSuite, KeyRegistryTestSuite) {
        super.setUp();

        idGateway = new IdGateway(address(idRegistry), address(storageRegistry), owner);

        vm.startPrank(owner);
        idRegistry.setIdGateway(address(idGateway));
        vm.stopPrank();

        addKnownContract(address(idGateway));
    }

    function _registerTo(
        address caller
    ) internal returns (uint256 fid) {
        fid = _registerWithRecovery(caller, address(0));
    }

    function _registerToWithRecovery(address caller, address recovery) internal returns (uint256 fid) {
        vm.prank(caller);
        (fid,) = idGateway.register(recovery);
    }

    function _registerFor(uint256 callerPk, uint40 _deadline) internal {
        _registerForWithRecovery(callerPk, address(0), _deadline);
    }

    function _registerForWithRecovery(uint256 callerPk, address recovery, uint40 _deadline) internal {
        uint256 deadline = _boundDeadline(_deadline);
        callerPk = _boundPk(callerPk);

        address caller = vm.addr(callerPk);
        bytes memory sig = _signRegister(callerPk, caller, recovery, deadline);

        vm.prank(caller);
        idGateway.registerFor(caller, recovery, deadline, sig);
    }

    function _signRegister(
        uint256 pk,
        address to,
        address recovery,
        uint256 deadline
    ) internal returns (bytes memory signature) {
        address signer = vm.addr(pk);
        bytes32 digest = idGateway.hashTypedDataV4(
            keccak256(abi.encode(idGateway.REGISTER_TYPEHASH(), to, recovery, idGateway.nonces(signer), deadline))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
