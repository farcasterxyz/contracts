// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry, IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract IdRegistryGasUsageTest is IdRegistryTestSuite {
    address constant TRUSTED_SENDER = address(0x123);
    address constant RECOVERY = address(0x6D1217BD164119E2ddE6ce1723879844FD73114e);

    // Perform actions many times to get a good median, since the first run initializes storage

    function testGasRegister() public {
        for (uint256 i = 1; i < 15; i++) {
            address caller = vm.addr(i);
            vm.prank(idRegistry.idManager());
            idRegistry.register(caller, RECOVERY);
            assertEq(idRegistry.idOf(caller), i);
        }
    }

    function testGasRegisterForAndRecover() public {
        for (uint256 i = 1; i < 15; i++) {
            address registrationRecipient = vm.addr(i);
            uint40 deadline = type(uint40).max;

            uint256 recoveryRecipientPk = i + 100;
            address recoveryRecipient = vm.addr(recoveryRecipientPk);

            vm.prank(idRegistry.idManager());
            uint256 fid = idRegistry.register(registrationRecipient, RECOVERY);
            assertEq(idRegistry.idOf(registrationRecipient), i);

            bytes memory transferSig = _signTransfer(recoveryRecipientPk, fid, recoveryRecipient, deadline);
            vm.prank(RECOVERY);
            idRegistry.recover(registrationRecipient, recoveryRecipient, deadline, transferSig);
        }
    }

    function testGasRegisterFromTrustedCaller() public {
        /* vm.prank(owner);
        idRegistry.setTrustedCaller(TRUSTED_SENDER);

        for (uint256 i = 0; i < 25; i++) {
            address alice = address(uint160(i));
            vm.prank(TRUSTED_SENDER);
            idRegistry.trustedRegister(alice, address(0));
            assertEq(idRegistry.idOf(alice), i + 1);
        } */
    }
}
