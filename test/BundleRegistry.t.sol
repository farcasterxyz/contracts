// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";

import {BundleRegistry} from "../src/BundleRegistry.sol";
import {BundleRegistryTestable} from "./Utils.sol";
import {IDRegistry} from "../src/IDRegistry.sol";
import {IDRegistryTestable} from "./Utils.sol";
import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */

contract BundleRegistryTest is Test {
    IDRegistryTestable idRegistry;
    NameRegistry nameRegistry;
    BundleRegistryTestable bundleRegistry;
    NameRegistry nameRegistryImpl;
    ERC1967Proxy nameRegistryProxy;

    event ChangeTrustedCaller(address indexed trustedCaller, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address[] knownContracts = [
        address(0xCe71065D4017F316EC606Fe4422e11eB2c47c246), // FuzzerDict
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C), // CREATE2 Factory
        address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), // address(this)
        address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A), // FORWARDER
        address(0x185a4dc360CE69bDCceE33b3784B0282f7961aea), // ???
        address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D) // ???
    ];

    address constant PRECOMPILE_CONTRACTS = address(9); // some addresses up to 0x9 are precompiled contracts

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);
    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address owner = address(this);

    uint256 constant DEC1_2022_TS = 1669881600; // Dec 1, 2022 00:00:00 GMT
    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT
    uint256 constant ALICE_TOKEN_ID = uint256(bytes32("alice"));
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

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

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret,
        string calldata url,
        uint256 amount
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        vm.assume(amount >= 0.01 ether); // the amount must be at least 0.01 ETH
        _assumeClean(relayer); // relayer must be able to receive funds
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted Registration is disabled in both registries, and trusted caller is not set
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + 60 seconds);

        vm.deal(relayer, amount);
        vm.prank(relayer);
        bundleRegistry.register{value: amount}(alice, recovery, url, "alice", secret);

        _assertSuccessfulRegistration(alice, recovery);

        // At most 0.0009 ETH of was consumed for gas + registration fees
        assertEq(relayer.balance > amount - 0.0009 ether, true);
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    function testCannotRegisterIfIDRegistryEnabledNameRegistryDisabled(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret,
        string calldata url
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        _assumeClean(relayer); // relayer must be able to receive funds
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is enabled in IDRegistry, but disabled in NameRegistry and
        // trusted caller is set in IDRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + 60 seconds);

        vm.deal(relayer, 1 ether);
        vm.prank(relayer);
        vm.expectRevert(IDRegistry.Invitable.selector);
        bundleRegistry.register{value: 0.01 ether}(alice, recovery, url, "alice", secret);

        _assertUnsuccessfulRegistration(alice);

        assertEq(relayer.balance, 1 ether);
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    function testCannotRegisterIfIDRegistryDisabledNameRegistryEnabled(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret,
        string calldata url
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        _assumeClean(relayer); // relayer must be able to receive funds
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is disabled in IDRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        vm.expectRevert(NameRegistry.Invitable.selector);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + 60 seconds);

        vm.deal(relayer, 1 ether);
        vm.prank(relayer);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        bundleRegistry.register{value: 1 ether}(alice, recovery, url, "alice", secret);

        _assertUnsuccessfulRegistration(alice);

        assertEq(relayer.balance, 1 ether);
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    function testCannotRegisterIfBothEnabled(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret,
        string calldata url
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        _assumeClean(relayer); // relayer must be able to receive funds
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is enabled in both registries and trusted caller is set in both
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        vm.expectRevert(NameRegistry.Invitable.selector);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + 60 seconds);

        vm.deal(relayer, 1 ether);
        vm.prank(relayer);
        vm.expectRevert(IDRegistry.Invitable.selector);
        bundleRegistry.register{value: 1 ether}(alice, recovery, url, "alice", secret);

        _assertUnsuccessfulRegistration(alice);

        assertEq(relayer.balance, 1 ether);
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTrustedRegister(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is enabled in both registries and trusted caller is set in both
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        bundleRegistry.trustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertSuccessfulRegistration(alice, recovery);
    }

    function testCannotTrustedRegisterFromUntrustedCaller(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee,
        address untrustedCaller
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry
        vm.assume(untrustedCaller != address(this)); // guarantees call from untrusted caller

        // State: Trusted registration is enabled in both registries and trusted caller is set in both
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        // Call is made from an address that is not address(this), since addres(this) is the deployer
        // and therefore the trusted caller for BundleRegistry
        vm.prank(untrustedCaller);
        vm.expectRevert(BundleRegistry.Unauthorized.selector);
        bundleRegistry.trustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    function testTrustedRegisterIfIDRegistryDisabledNameRegistryEnabled(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is disabled in IDRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.Registrable.selector);
        bundleRegistry.trustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    function testTrustedRegisterIfIDRegistryEnabledNameRegistryDisabled(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is enabled in IDRegistry, but disabled in NameRegistry and
        // trusted caller is set in IDRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.NotInvitable.selector);
        bundleRegistry.trustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    function testTrustedRegisterIfBothDisabled(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is disabled in both registries
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.Registrable.selector);
        bundleRegistry.trustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    /*//////////////////////////////////////////////////////////////
                     PARTIAL TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testPartialTrustedRegister(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is disabled in IDRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        bundleRegistry.partialTrustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertSuccessfulRegistration(alice, recovery);
    }

    function testCannotPartialTrustedRegisterIfBothEnabled(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is enabled in both registries and trusted caller is set
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        vm.expectRevert(IDRegistry.Invitable.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    function testCannotPartialTrustedRegisterIfIDRegistryEnabledNameRegistryDisabled(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is enabled in IDRegistry, but disabled in NameRegistry and
        // trusted caller is set in IDRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(IDRegistry.Invitable.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    function testCannotPartialTrustedRegisterIfBothDisabled(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry

        // State: Trusted registration is disabled in both registries and trusted caller is not sset
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.NotInvitable.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    function testCannotPartialTrustedRegisterUnlessTrustedCaller(
        address alice,
        address recovery,
        string calldata url,
        uint256 inviter,
        uint256 invitee,
        address untrustedCaller
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.warp(DEC1_2022_TS); // Block timestamp must be >= 2022 to call the NameRegistry
        vm.assume(untrustedCaller != bundleRegistry.getTrustedCaller());

        // State: Trusted registration is disabled in IDRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        // Call is made from an address that is not address(this), since address(this) is the
        // deployer and therefore the trusted caller for BundleRegistry
        vm.prank(untrustedCaller);
        vm.expectRevert(BundleRegistry.Unauthorized.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, url, "alice", inviter, invitee);

        _assertUnsuccessfulRegistration(alice);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeTrustedCaller(address alice) public {
        vm.assume(alice != FORWARDER);
        assertEq(bundleRegistry.owner(), owner);

        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedCaller(alice, address(this));
        bundleRegistry.changeTrustedCaller(alice);
        assertEq(bundleRegistry.getTrustedCaller(), alice);
    }

    function testCannotChangeTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(bundleRegistry.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bundleRegistry.changeTrustedCaller(bob);
        assertEq(bundleRegistry.getTrustedCaller(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    // Ensures that a fuzzed address input does not match a known contract address
    function _assumeClean(address a) internal {
        // TODO: extract the general assume functions into a utils so it can be shared with NameRegistry.t.sol
        for (uint256 i = 0; i < knownContracts.length; i++) {
            vm.assume(a != knownContracts[i]);
        }

        vm.assume(a > PRECOMPILE_CONTRACTS);
        vm.assume(a != ADMIN);
    }

    // Assert that a given fname was correctly registered with id 1 and recovery
    function _assertSuccessfulRegistration(address alice, address recovery) internal {
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    // Assert that a given fname was not registered and the contracts have no registrations
    function _assertUnsuccessfulRegistration(address alice) internal {
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }
}
