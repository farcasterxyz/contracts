// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {IDRegistryTestable} from "./Utils.sol";
import {BundleRegistryTestable} from "./Utils.sol";
import {NameRegistry} from "../src/NameRegistry.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* solhint-disable state-visibility */

contract BundleRegistryGasUsageTest is Test {
    IDRegistryTestable idRegistry;
    NameRegistry nameRegistry;
    BundleRegistryTestable bundleRegistry;
    NameRegistry nameRegistryImpl;
    ERC1967Proxy nameRegistryProxy;

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);
    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address owner = address(this);

    uint256 constant DEC1_2022_TS = 1669881600; // Dec 1, 2022 00:00:00 GMT
    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT
    uint256 constant ALICE_TOKEN_ID = uint256(bytes32("alice"));
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address constant RECOVERY = address(0x456);

    string constant URL = "https://farcaster.xyz";

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
    ]; // padded to all be length 5

    function setUp() public {
        // Set up the IDRegistry
        idRegistry = new IDRegistryTestable(FORWARDER);

        // Set up the NameRegistry with UUPS Proxy and configure the admin role
        nameRegistryImpl = new NameRegistry(FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);

        // Set up the BundleRegistry
        bundleRegistry = new BundleRegistryTestable(address(idRegistry), address(nameRegistry), address(this));
    }

    function testGasRegister() public {
        idRegistry.disableTrustedRegister();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedRegister();

        for (uint256 i = 0; i < 10; i++) {
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
            vm.warp(block.timestamp + 60 seconds);
            uint256 balance = alice.balance;
            vm.prank(alice);
            bundleRegistry.register{value: 0.01 ether}(alice, RECOVERY, URL, name, "secret");

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2023_TS);
            assertEq(alice.balance, balance - nameRegistry.currYearFee());
            assertEq(nameRegistry.recoveryOf(nameTokenId), RECOVERY);
        }
    }

    function testGasTrustedRegister() public {
        vm.warp(DEC1_2022_TS);

        for (uint256 i = 0; i < 10; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            idRegistry.changeTrustedSender(address(bundleRegistry));
            vm.prank(ADMIN);
            nameRegistry.changeTrustedSender(address(bundleRegistry));

            // 3. Register the name alice
            vm.warp(block.timestamp + 60 seconds);
            bundleRegistry.trustedRegister(alice, RECOVERY, URL, name, 1, 2);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2023_TS);
            assertEq(nameRegistry.recoveryOf(nameTokenId), RECOVERY);
        }
    }
}
