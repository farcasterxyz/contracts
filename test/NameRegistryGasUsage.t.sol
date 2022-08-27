// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {NameRegistry} from "../src/NameRegistry.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* solhint-disable state-visibility */

contract NameRegistryGasUsageTest is Test {
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    ERC1967Proxy nameRegistryProxy;

    address vault = address(this);
    address owner = address(this);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address constant TRUSTED_FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    uint256 constant COMMIT_REGISTER_DELAY = 60;

    uint256 constant DEC1_2022_TS = 1669881600; // Dec 1, 2022 00:00:00 GMT
    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT
    uint256 constant JAN1_2024_TS = 1704067200; // Jan 1, 2024 0:00:00 GMT
    uint256 constant JAN31_2024_TS = 1706659200; // Jan 31, 2024 0:00:00 GMT
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
    ]; // padded to all be length 5

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        nameRegistryImpl = new NameRegistry(TRUSTED_FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", vault);
    }

    function testGasUsage() public {
        vm.prank(owner);
        nameRegistry.disableTrustedRegister();

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
            nameRegistry.register{value: 0.01 ether}(name, alice, "secret", address(0x456));

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2023_TS);
            assertEq(alice.balance, balance - nameRegistry.currYearFee());
            assertEq(nameRegistry.recoveryOf(nameTokenId), address(0x456));
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
            vm.warp(JAN31_2024_TS);

            vm.prank(alice);
            nameRegistry.bid{value: 1_000.01 ether}(nameTokenId, address(0x456));

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(nameRegistry.balanceOf(alice), 1);
            assertEq(nameRegistry.expiryOf(nameTokenId), JAN1_2025_TS);
            assertEq(nameRegistry.recoveryOf(nameTokenId), address(0x456));

            vm.prank(alice);
            nameRegistry.transferFrom(alice, bob, nameTokenId);

            assertEq(nameRegistry.ownerOf(nameTokenId), bob);
            assertEq(nameRegistry.balanceOf(alice), 0);
            assertEq(nameRegistry.balanceOf(bob), 1);
        }
    }
}
