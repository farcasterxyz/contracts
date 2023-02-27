// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";

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

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant RECOVERY = address(0x8Ca9aB5b1756B7020a299ff4dc79b5E854a5cac5);
    address constant TRUSTED_SENDER = address(0x4E29ad5578668e2f82A921FFd5fA7720eDD59D47);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);

    uint256 constant COMMIT_REGISTER_DELAY = 60;
    uint256 constant RENEWAL_PERIOD = 30 days;
    uint256 constant REGISTRATION_PERIOD = 365 days;

    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT

    bytes16[10] names =
        [bytes16("alice"), "bob11", "carol", "dave1", "eve11", "frank", "georg", "harry", "ian11", "jane1"]; // padded to be length 5

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

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
            // Add +10 to the integer to skip the precompile contracts
            address alice = address(uint160(i) + 10);
            vm.deal(alice, 10_000 ether);

            // Add +100 to avoid collision with alice in all instances
            address bob = address(uint160(i) + 100);

            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            // Make the first commit on Jan 1, 2023
            vm.warp(JAN1_2023_TS);
            bytes32 commitHash = nameRegistry.generateCommit(name, alice, "secret", RECOVERY);

            vm.prank(alice);
            nameRegistry.makeCommit(commitHash);
            assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);

            // Register the name after the commit register delay has elapsed
            vm.warp(block.timestamp + COMMIT_REGISTER_DELAY);
            uint256 balance = alice.balance;
            vm.prank(alice);
            nameRegistry.register{value: 0.01 ether}(name, alice, "secret", RECOVERY);

            uint256 firstExpiration = block.timestamp + REGISTRATION_PERIOD;

            (address _recovery, uint256 _expiry) = nameRegistry.registrationMetadataOf(nameTokenId);
            assertEq(_expiry, firstExpiration);
            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(_recovery, RECOVERY);
            assertEq(alice.balance, balance - nameRegistry.fee());

            // Wait until the registration expires, then renew the registration for a year
            vm.warp(firstExpiration);
            vm.prank(alice);
            nameRegistry.renew{value: 0.01 ether}(nameTokenId);

            uint256 secondExpiration = block.timestamp + REGISTRATION_PERIOD;
            (, _expiry) = nameRegistry.registrationMetadataOf(nameTokenId);
            assertEq(_expiry, secondExpiration);
            assertEq(nameRegistry.ownerOf(nameTokenId), alice);

            // Wait until the second registration expires, then wait for the renewal period to pass
            // and finally bid on the name
            vm.warp(secondExpiration + RENEWAL_PERIOD);
            vm.prank(alice);
            nameRegistry.bid{value: 1_000.01 ether}(alice, nameTokenId, RECOVERY);

            assertEq(nameRegistry.balanceOf(alice), 1);
            (_recovery, _expiry) = nameRegistry.registrationMetadataOf(nameTokenId);
            assertEq(_expiry, block.timestamp + REGISTRATION_PERIOD);
            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(_recovery, RECOVERY);

            // Transfer the name to a new owner
            vm.prank(alice);
            nameRegistry.transferFrom(alice, bob, nameTokenId);

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

            uint256 inviterId = 5;
            uint256 inviteeId = 6;

            vm.deal(alice, 10_000 ether);
            vm.warp(JAN1_2023_TS);

            vm.prank(TRUSTED_SENDER);
            nameRegistry.trustedRegister(name, alice, RECOVERY, inviterId, inviteeId);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            (address _recovery, uint256 _expiry) = nameRegistry.registrationMetadataOf(nameTokenId);
            assertEq(_expiry, block.timestamp + REGISTRATION_PERIOD);
            assertEq(_recovery, RECOVERY);
        }
    }
}
