// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IdGatewayTestSuite} from "./IdGatewayTestSuite.sol";

/* solhint-disable state-visibility */

contract IdGatewayGasUsageTest is IdGatewayTestSuite {
    address constant RECOVERY = address(0x6D1217BD164119E2ddE6ce1723879844FD73114e);

    // Perform actions many times to get a good median, since the first run initializes storage

    function testGasRegister() public {
        for (uint256 i = 1; i < 15; i++) {
            address caller = vm.addr(i);
            uint256 fee = idGateway.price();
            vm.deal(caller, fee);
            vm.prank(caller);
            idGateway.register{value: fee}(RECOVERY);
            assertEq(idRegistry.idOf(caller), i);
        }
    }

    function testGasRegisterForAndRecover() public {
        for (uint256 i = 1; i < 15; i++) {
            address registrationRecipient = vm.addr(i);
            uint40 deadline = type(uint40).max;

            uint256 recoveryRecipientPk = i + 100;
            address recoveryRecipient = vm.addr(recoveryRecipientPk);

            uint256 fee = idGateway.price();
            vm.deal(registrationRecipient, fee);
            vm.prank(registrationRecipient);
            (uint256 fid,) = idGateway.register{value: fee}(RECOVERY);
            assertEq(idRegistry.idOf(registrationRecipient), i);

            bytes memory transferSig = _signTransfer(recoveryRecipientPk, fid, recoveryRecipient, deadline);
            vm.prank(RECOVERY);
            idRegistry.recover(registrationRecipient, recoveryRecipient, deadline, transferSig);
        }
    }
}
