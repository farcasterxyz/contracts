// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */

contract NameRegistryGasUsageTest is Test {
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    ERC1967Proxy nameRegistryProxy;

    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address constant TRUSTED_FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    uint256 constant COMMIT_REGISTER_DELAY = 60;
    address constant RECOVERY = address(0x8Ca9aB5b1756B7020a299ff4dc79b5E854a5cac5);
    address constant TRUSTED_SENDER = address(0x4E29ad5578668e2f82A921FFd5fA7720eDD59D47);

    uint256 constant DEC1_2022_TS = 1669881600; // Dec 1, 2022 00:00:00 GMT
    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT
    uint256 constant JAN1_2024_TS = 1704067200; // Jan 1, 2024 0:00:00 GMT
    uint256 constant FEB1_2024_TS = 1706745600; // Feb 1, 2024 0:00:00 GMT
    uint256 constant JAN1_2025_TS = 1735689600; // Jan 1, 2025 0:00:00 GMT

    bytes16[10] names = [
        bytes16("alice"),
        "bob11",
        "carol",
        "dave1",
        "eve11",
        "frank",
        "georg",
        "harry",
        "ian11",
        "jane1"
    ]; // padded to be length 5

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        nameRegistryImpl = new NameRegistry(TRUSTED_FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);
    }

    function testGasRegisterUsage() public {
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        // 1. During 2022, test making the commit and registering the name
        for (uint256 i = 0; i < names.length; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            bytes32 commitHash = nameRegistry.generateCommit(name, alice, "secret");

            vm.deal(alice, 10_000 ether);
            vm.warp(DEC1_2022_TS);

            vm.prank(alice);
            nameRegistry.makeCommit(commitHash);
            assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);

            // 3. Register the name alice
            vm.warp(block.timestamp + COMMIT_REGISTER_DELAY);
            uint256 balance = alice.balance;
            vm.prank(alice);
            nameRegistry.register{value: 0.01 ether}(name, alice, "secret", RECOVERY);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2023_TS);
            assertEq(alice.balance, balance - nameRegistry.currYearFee());
            assertEq(nameRegistry.recoveryOf(nameTokenId), RECOVERY);
        }

        // 2. During 2023, test renewing the name after it expires. This must not be done in the previous
        // loop since warping forward and triggering the currYear calculation will cause issues if we ever
        // warp backwards into the previous year.
        for (uint256 i = 0; i < names.length; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));
            vm.warp(JAN1_2023_TS);

            vm.prank(alice);
            nameRegistry.renew{value: 0.01 ether}(nameTokenId);
            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2024_TS);
        }

        // 3. During 2024, test bidding on the name after it expires and then transferring it. This is also
        // done in a separate loop for the same reason as 2
        for (uint256 i = 0; i < names.length; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            address bob = address(uint160(i) + 100);
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));
            vm.warp(FEB1_2024_TS);

            vm.prank(alice);
            nameRegistry.bid{value: 1_000.01 ether}(alice, nameTokenId, RECOVERY);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.balanceOf(alice), 1);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2025_TS);
            assertEq(nameRegistry.recoveryOf(nameTokenId), RECOVERY);

            vm.prank(alice);
            nameRegistry.transferFrom(alice, bob, nameTokenId);

            assertEq(nameRegistry.ownerOf(nameTokenId), bob);
            assertEq(nameRegistry.balanceOf(alice), 0);
            assertEq(nameRegistry.balanceOf(bob), 1);
        }
    }

    function testGasTrustedRegisterUsage() public {
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(TRUSTED_SENDER);

        for (uint256 i = 0; i < names.length; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            uint256 inviterId = 5;
            uint256 inviteeId = 6;

            vm.deal(alice, 10_000 ether);
            vm.warp(DEC1_2022_TS);

            vm.prank(TRUSTED_SENDER);
            nameRegistry.trustedRegister(name, alice, RECOVERY, inviterId, inviteeId);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2023_TS);
            assertEq(nameRegistry.recoveryOf(nameTokenId), RECOVERY);
        }
    }
}
