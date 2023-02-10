// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./NameRegistryBaseTest.sol";

contract IntegrationTest is NameRegistryBaseTest {
    function testRegisterAfterUnpausing(address alice, address recovery, bytes32 secret, uint256 delay) public {
        _assumeClean(alice);
        // _assumeClean(recovery);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= COMMIT_REVEAL_DELAY);
        _disableTrusted();
        _grant(OPERATOR_ROLE, ADMIN);

        // 1. Make commitment to register the name @alice
        vm.deal(alice, 1 ether);
        vm.warp(JAN1_2023_TS);
        vm.prank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(commitHash);

        // 2. Fast forward past the register delay and pause and unpause the contract
        vm.warp(block.timestamp + delay);
        vm.prank(ADMIN);
        nameRegistry.pause();
        vm.prank(ADMIN);
        nameRegistry.unpause();

        // 3. Register the name alice
        vm.prank(alice);
        nameRegistry.register{value: FEE}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }
}
