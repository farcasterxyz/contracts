// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./NameRegistryConstants.sol";
import "./TestConstants.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */

contract NameRegistryGasUsageTest is Test {
    /// Instance of the implementation contract
    NameRegistry nameRegistryImpl;

    // Instance of the proxy contract
    ERC1967Proxy nameRegistryProxy;

    // Instance of the proxy contract cast as the implementation contract
    NameRegistry nameRegistry;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address constant TRUSTED_SENDER = address(0x4E29ad5578668e2f82A921FFd5fA7720eDD59D47);

    // names are padded to 5 characters
    bytes16[10] names =
        [bytes16("alice"), "bob11", "carol", "dave1", "eve11", "frank", "georg", "harry", "ian11", "jane1"];

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        nameRegistryImpl = new NameRegistry(FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");

        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);
    }

    function testGasRegister() public {
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        for (uint256 i = 0; i < names.length; i++) {
            address alice = address(uint160(i) + 10); // Add +10 to avoid precompile contracts
            address bob = address(uint160(i) + 100); // Add +100 to avoid collision with all alice
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            vm.deal(alice, 10_000 ether);

            /* Make the first commit */
            vm.warp(10_000); // Avoid CommitReplay() false positive at block.timestamp == 0
            bytes32 commitHash = nameRegistry.generateCommit(name, alice, "secret", RECOVERY);

            vm.prank(alice);
            nameRegistry.makeCommit(commitHash);
            assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);

            /* Register the name after the commit register delay */
            vm.warp(block.timestamp + COMMIT_REGISTER_DELAY);
            uint256 balance = alice.balance;
            vm.prank(alice);
            nameRegistry.register{value: 0.01 ether}(name, alice, "secret", RECOVERY);

            uint256 firstExpiration = block.timestamp + REGISTRATION_PERIOD;
            (address _recovery, uint256 _expiry) = nameRegistry.metadataOf(nameTokenId);
            assertEq(_expiry, firstExpiration);
            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(_recovery, RECOVERY);
            assertEq(alice.balance, balance - nameRegistry.fee());

            /* Let the name expire and renew it before it goes up for bidding */
            vm.warp(firstExpiration);
            vm.prank(alice);
            nameRegistry.renew{value: 0.01 ether}(nameTokenId);

            uint256 secondExpiration = block.timestamp + REGISTRATION_PERIOD;
            (, _expiry) = nameRegistry.metadataOf(nameTokenId);
            assertEq(_expiry, secondExpiration);
            assertEq(nameRegistry.ownerOf(nameTokenId), alice);

            /* Let the name expire and go up for bidding and then bid on it */
            vm.warp(secondExpiration + RENEWAL_PERIOD);
            vm.prank(alice);
            nameRegistry.bid{value: 1_000.01 ether}(alice, nameTokenId, RECOVERY);

            assertEq(nameRegistry.balanceOf(alice), 1);
            (_recovery, _expiry) = nameRegistry.metadataOf(nameTokenId);
            assertEq(_expiry, block.timestamp + REGISTRATION_PERIOD);
            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(_recovery, RECOVERY);

            /* Request and cancel a recovery */
            vm.prank(RECOVERY);
            nameRegistry.requestRecovery(nameTokenId, bob);

            vm.prank(alice);
            nameRegistry.cancelRecovery(nameTokenId);

            /* Either transfer the name or request and complete a recovery */
            if (i < 5) {
                vm.prank(alice);
                nameRegistry.transferFrom(alice, bob, nameTokenId);
            } else {
                vm.prank(RECOVERY);
                nameRegistry.requestRecovery(nameTokenId, bob);

                vm.warp(block.timestamp + 7 days);
                vm.prank(RECOVERY);
                nameRegistry.completeRecovery(nameTokenId);
            }

            assertEq(nameRegistry.ownerOf(nameTokenId), bob);
            assertEq(nameRegistry.balanceOf(alice), 0);
            assertEq(nameRegistry.balanceOf(bob), 1);
        }
    }

    function testGasTrustedRegister() public {
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(TRUSTED_SENDER);

        for (uint256 i = 0; i < names.length; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            vm.deal(alice, 10_000 ether);
            vm.warp(JAN1_2023_TS);

            vm.prank(TRUSTED_SENDER);
            nameRegistry.trustedRegister(name, alice, RECOVERY);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            (address _recovery, uint256 _expiry) = nameRegistry.metadataOf(nameTokenId);
            assertEq(_expiry, block.timestamp + REGISTRATION_PERIOD);
            assertEq(_recovery, RECOVERY);
        }
    }
}
