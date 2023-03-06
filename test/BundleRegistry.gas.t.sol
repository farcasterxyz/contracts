// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./NameRegistryConstants.sol";
import "./TestConstants.sol";
import {BundleRegistryHarness} from "./Utils.sol";
import {IdRegistryHarness} from "./Utils.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */

contract BundleRegistryGasUsageTest is Test {
    IdRegistryHarness idRegistry;
    NameRegistry nameRegistry;
    BundleRegistryHarness bundleRegistry;
    NameRegistry nameRegistryImpl;
    ERC1967Proxy nameRegistryProxy;

    address owner = address(this);

    // padded to all be length 5
    bytes16[10] names =
        [bytes16("alice"), "bob11", "carol", "dave1", "eve11", "frank", "georg", "harry", "ian11", "jane1"];

    function setUp() public {
        // Set up the IdRegistry
        idRegistry = new IdRegistryHarness(FORWARDER);

        // Set up the NameRegistry with UUPS Proxy and configure the admin role
        nameRegistryImpl = new NameRegistry(FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);

        // Set up the BundleRegistry
        bundleRegistry = new BundleRegistryHarness(
            address(idRegistry),
            address(nameRegistry),
            address(this)
        );
    }

    function testGasRegister() public {
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        uint256 commitTs = DEC1_2022_TS;
        uint256 registerTs = commitTs + COMMIT_REGISTER_DELAY;
        uint256 renewableTs = registerTs + 365 days;

        for (uint256 i = 0; i < 10; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            bytes32 commitHash = nameRegistry.generateCommit(name, alice, "secret", RECOVERY);

            vm.deal(alice, 10_000 ether);
            vm.warp(commitTs);

            vm.prank(alice);
            nameRegistry.makeCommit(commitHash);
            assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);

            // 3. Register the name alice
            vm.warp(registerTs);
            uint256 balance = alice.balance;
            vm.prank(alice);
            bundleRegistry.register{value: 0.01 ether}(alice, RECOVERY, name, "secret");
            (address recovery, uint40 expiryTs) = nameRegistry.metadataOf(nameTokenId);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            assertEq(expiryTs, renewableTs);
            assertEq(alice.balance, balance - nameRegistry.fee());
            assertEq(recovery, RECOVERY);
        }
    }

    function testGasTrustedRegister() public {
        vm.warp(DEC1_2022_TS);

        for (uint256 i = 0; i < 10; i++) {
            address alice = address(uint160(i) + 10); // start after the precompiles
            bytes16 name = names[i];
            uint256 nameTokenId = uint256(bytes32(name));

            idRegistry.changeTrustedCaller(address(bundleRegistry));
            vm.prank(ADMIN);
            nameRegistry.changeTrustedCaller(address(bundleRegistry));

            // 3. Register the name alice
            vm.warp(block.timestamp + 60 seconds);
            bundleRegistry.trustedRegister(alice, RECOVERY, name);

            assertEq(nameRegistry.ownerOf(nameTokenId), alice);
            (address recovery, uint40 expiryTs) = nameRegistry.metadataOf(nameTokenId);
            assertEq(expiryTs, block.timestamp + 365 days);
            assertEq(recovery, RECOVERY);
        }
    }
}
