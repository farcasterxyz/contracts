// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {NameRegistry} from "../src/NameRegistry.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

/* solhint-disable state-visibility */
/* solhint-disable max-states-count */
/* solhint-disable avoid-low-level-calls */

contract NameRegistryTest is Test {
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    ERC1967Proxy nameRegistryProxy;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Renew(uint256 indexed tokenId, uint256 expiry);
    event ChangeRecoveryAddress(uint256 indexed tokenId, address indexed recovery);
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed id);
    event CancelRecovery(uint256 indexed id);
    event ChangeVault(address indexed vault);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address defaultAdmin = address(this);
    address vault = address(0x123456);

    // Known contracts that must not be made to call other contracts in tests
    address[] knownContracts = [
        address(0xCe71065D4017F316EC606Fe4422e11eB2c47c246), // FuzzerDict
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C), // CREATE2 Factory
        address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), // address(this)
        address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A), // FORWARDER
        address(0x185a4dc360CE69bDCceE33b3784B0282f7961aea), // ???
        address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D) // ???
    ];

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant PRECOMPILE_CONTRACTS = address(9); // some addresses up to 0x9 are precompiled contracts

    uint256 constant ESCROW_PERIOD = 3 days;
    uint256 constant COMMIT_PERIOD = 60 seconds;

    uint256 constant DEC1_2022_TS = 1669881600; // Dec 1, 2022 00:00:00 GMT
    uint256 constant JAN1_2022_TS = 1640995200; // Jan 1, 2022 0:00:00 GMT
    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT
    uint256 constant JAN31_2023_TS = 1675123200; // Jan 31, 2023 0:00:00 GMT
    uint256 constant JAN1_2024_TS = 1704067200; // Jan 1, 2024 0:00:00 GMT

    uint256 constant ALICE_TOKEN_ID = uint256(bytes32("alice"));
    uint256 constant BOB_TOKEN_ID = uint256(bytes32("bob"));

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        nameRegistryImpl = new NameRegistry(FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", vault);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);
    }

    /*//////////////////////////////////////////////////////////////
                              COMMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGenerateCommit(address) public {
        address alice = address(0x123);

        // alphabetic name
        bytes32 commit1 = nameRegistry.generateCommit("alice", alice, "secret");
        assertEq(commit1, 0xe89b588f69839d6c3411027709e47c05713159feefc87e3173f64c01f4b41c72);

        // 1-char name
        bytes32 commit2 = nameRegistry.generateCommit("1", alice, "secret");
        assertEq(commit2, 0xf52e7be4097c2afdc86002c691c7e5fab52be36748174fe15303bb32cb106da6);

        // 16-char alphabetic
        bytes32 commit3 = nameRegistry.generateCommit("alicenwonderland", alice, "secret");
        assertEq(commit3, 0x94f5dd34daadfe7565398163e7cb955832b2a2e963a6365346ab8ba92b5f5126);

        // 16-char alphanumeric name
        bytes32 commit4 = nameRegistry.generateCommit("alice0wonderland", alice, "secret");
        assertEq(commit4, 0xdf1dc48666da9fcc229a254aa77ffab008da2d29b617fada59b645b7cc0928b9);

        // 16-char alphanumeric hyphenated name
        bytes32 commit5 = nameRegistry.generateCommit("al1c3-w0nderl4nd", alice, "secret");
        assertEq(commit5, 0xbf29b096d3867cc3f3d913d0ee76882adbfa28f28d73bbe372218bd7b282189b);
    }

    function testCannotGenerateCommitWithInvalidName(address alice) public {
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("Alice", alice, "secret");

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a/lice", alice, "secret");

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a:lice", alice, "secret");

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a`ice", alice, "secret");

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a{ice", alice, "secret");

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("-alice", alice, "secret");

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(" alice", alice, "secret");

        bytes16 blankName = 0x00000000000000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(blankName, alice, "secret");

        // Should reject "a�ice", where � == 129 which is an invalid ASCII character
        bytes16 nameWithInvalidAsciiChar = 0x61816963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithInvalidAsciiChar, alice, "secret");

        // Should reject "a�ice", where � == NULL
        bytes16 nameWithEmptyByte = 0x61006963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithEmptyByte, alice, "secret");

        // Should reject "�lice", where � == NULL
        bytes16 nameWithStartingEmptyByte = 0x006c6963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithStartingEmptyByte, alice, "secret");
    }

    function testMakeCommit(address alice) public {
        vm.prank(ADMIN);
        nameRegistry.disableTrustedRegister();
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, "secret");

        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);
    }

    function testCannotMakeCommitDuringTrustedRegister(address alice) public {
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, "secret");
        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotRegistrable.selector);
        nameRegistry.makeCommit(commitHash);
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister(
        address alice,
        address charlie,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        // TODO: Implement fuzzing for name using valid name generator

        // 1. Give alice money and fast forward to 2022 to begin registration.
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        // 2. Make the commitment to register the name alice
        vm.startPrank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);

        // 3. Register the name alice
        vm.warp(block.timestamp + COMMIT_PERIOD);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, uint256(bytes32("alice")));
        uint256 balance = alice.balance;
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, charlie);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(alice.balance, balance - nameRegistry.currYearFee());
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), charlie);
        vm.stopPrank();
    }

    function testRegisterToAnotherAddress(
        address alice,
        address bob,
        bytes32 secret
    ) public {
        vm.assume(bob != address(0));
        _assumeClean(alice);
        _disableTrusted();

        // 1. Give alice money and fast forward to 2022 to begin registration.
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        // 2. Make the commitment to register the name @bob to the user bob
        vm.prank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("bob", bob, secret);
        nameRegistry.makeCommit(commitHash);

        // 3. Register the name @bob to bob
        vm.warp(block.timestamp + COMMIT_PERIOD);
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), bob, uint256(bytes32("bob")));
        vm.prank(alice);
        nameRegistry.register{value: 0.01 ether}("bob", bob, secret, address(0));

        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), bob);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), JAN1_2023_TS);
    }

    function testRegisterWorksWhenAlreadyOwningAName(address alice, bytes32 secret) public {
        _assumeClean(alice);
        _disableTrusted();

        // 1. Give alice money and fast forward to 2022 to begin registration.
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);
        vm.startPrank(alice);

        // 2. Register @alice to alice
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + COMMIT_PERIOD);
        nameRegistry.register{value: nameRegistry.fee()}("alice", alice, secret, address(0));

        // 3. Register @bob to alice
        bytes32 commitHashBob = nameRegistry.generateCommit("bob", alice, secret);
        nameRegistry.makeCommit(commitHashBob);
        vm.warp(block.timestamp + COMMIT_PERIOD);
        nameRegistry.register{value: 0.01 ether}("bob", alice, secret, address(0));

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(alice), 2);
        vm.stopPrank();
    }

    function testRegisterAfterUnpausing(
        address alice,
        address bob,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _disableTrusted();
        _grant(OPERATOR_ROLE, ADMIN);

        // 1. Make commitment to register the name @alice
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);
        vm.prank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);

        // 2. Fast forward past the register delay and pause and unpause the contract
        vm.warp(block.timestamp + COMMIT_PERIOD);
        vm.prank(ADMIN);
        nameRegistry.pause();
        vm.prank(ADMIN);
        nameRegistry.unpause();

        // 3. Register the name alice
        vm.prank(alice);
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, bob);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
    }

    function testCannotRegisterTheSameNameTwice(
        address alice,
        address bob,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _disableTrusted();

        vm.prank(ADMIN);
        nameRegistry.disableTrustedRegister();

        // 1. Give alice and bob money and have alice register @alice
        vm.startPrank(alice);
        vm.deal(alice, 10_000 ether);
        vm.deal(bob, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes32 aliceCommitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(aliceCommitHash);
        vm.warp(block.timestamp + COMMIT_PERIOD);
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, address(0));

        // 2. alice tries to register @alice again and fails
        nameRegistry.makeCommit(aliceCommitHash);
        vm.expectRevert(NameRegistry.NotRegistrable.selector);
        vm.warp(block.timestamp + COMMIT_PERIOD);
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, address(0));

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.stopPrank();

        // 3. bob tries to register @alice and fails
        vm.startPrank(bob);
        bytes32 bobCommitHash = nameRegistry.generateCommit("alice", bob, secret);
        nameRegistry.makeCommit(bobCommitHash);
        vm.expectRevert(NameRegistry.NotRegistrable.selector);
        vm.warp(block.timestamp + COMMIT_PERIOD);
        nameRegistry.register{value: 0.01 ether}("alice", bob, secret, address(0));

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.stopPrank();
    }

    function testCannotRegisterWithoutPayment(address alice, bytes32 secret) public {
        _assumeClean(alice);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.register{value: 1 wei}("alice", alice, secret, address(0));
    }

    function testCannotRegisterWithoutCommit(
        address alice,
        address bob,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}(username, bob, secret, address(0));
    }

    function testCannotRegisterWithInvalidCommitSecret(
        address alice,
        address bob,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        bytes32 incorrectSecret = "foobar";
        vm.assume(secret != incorrectSecret);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}(username, bob, incorrectSecret, address(0));
    }

    function testCannotRegisterWithInvalidCommitAddress(
        address alice,
        address bob,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        address incorrectOwner = address(0x1234A);
        vm.assume(bob != incorrectOwner);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}(username, incorrectOwner, secret, address(0));
    }

    function testCannotRegisterWithInvalidCommitName(
        address alice,
        address bob,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        bytes16 incorrectUsername = "alice";
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        vm.prank(alice);
        nameRegistry.register{value: 0.01 ether}(incorrectUsername, bob, secret, address(0));
    }

    function testCannotRegisterBeforeDelay(address alice, bytes32 secret) public {
        _assumeClean(alice);
        _disableTrusted();

        // 1. Give alice money and fast forward to 2022 to begin registration.
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        // 2. Make the commitment to register the name alice
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        // 3. Try to register the name and fail
        vm.warp(block.timestamp + COMMIT_PERIOD - 1);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, address(0));
    }

    function testCannotRegisterWithInvalidNames(address alice, bytes32 secret) public {
        _assumeClean(alice);
        _disableTrusted();

        bytes16 incorrectUsername = "al{ce";
        bytes32 invalidCommit = keccak256(abi.encode(incorrectUsername, alice, secret));
        nameRegistry.makeCommit(invalidCommit);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.register{value: 0.01 ether}(incorrectUsername, alice, secret, address(0));
    }

    function testCannotRegisterWhenPaused(address alice, address bob) public {
        _assumeClean(alice);
        _disableTrusted();
        _grant(OPERATOR_ROLE, ADMIN);

        // 1. Make the commitment to register @alice
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);
        vm.prank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, "secret");
        nameRegistry.makeCommit(commitHash);

        // 2. Pause the contract and try to register the name alice
        vm.warp(block.timestamp + COMMIT_PERIOD);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.register{value: 0.01 ether}("alice", alice, "secret", bob);

        vm.expectRevert(NameRegistry.Registrable.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         REGISTER TRUSTED TESTS
    //////////////////////////////////////////////////////////////*/

    function testTrustedRegister(address trustedSender, address alice) public {
        vm.assume(alice != address(0));
        vm.assume(trustedSender != FORWARDER);

        vm.warp(JAN1_2022_TS);
        vm.prank(ADMIN);
        nameRegistry.setTrustedSender(trustedSender);
        assertEq(nameRegistry.trustedRegisterEnabled(), 1);

        vm.prank(trustedSender);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, ALICE_TOKEN_ID);
        nameRegistry.trustedRegister(alice, "alice", address(0));

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    function testTrustedRegisterSetsRecoveryAddress(
        address trustedSender,
        address alice,
        address bob
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedSender != FORWARDER);

        vm.prank(ADMIN);
        nameRegistry.setTrustedSender(trustedSender);
        assertEq(nameRegistry.trustedRegisterEnabled(), 1);

        vm.prank(trustedSender);
        nameRegistry.trustedRegister(alice, "alice", bob);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
    }

    function testCannotTrustedRegisterWhenDisabled(address trustedSender, address alice) public {
        vm.assume(alice != address(0));
        vm.assume(trustedSender != FORWARDER);

        vm.prank(ADMIN);
        nameRegistry.setTrustedSender(trustedSender);

        vm.prank(ADMIN);
        nameRegistry.disableTrustedRegister();

        vm.prank(trustedSender);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.trustedRegister(alice, "alice", address(0));

        vm.expectRevert(NameRegistry.Registrable.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotTrustedRegisterTwice(address trustedSender, address alice) public {
        vm.assume(alice != address(0));
        vm.assume(trustedSender != FORWARDER);

        vm.prank(ADMIN);
        nameRegistry.setTrustedSender(trustedSender);
        assertEq(nameRegistry.trustedRegisterEnabled(), 1);

        vm.prank(trustedSender);
        nameRegistry.trustedRegister(alice, "alice", address(0));

        vm.prank(trustedSender);
        vm.expectRevert("ERC721: token already minted");
        nameRegistry.trustedRegister(alice, "alice", address(0));
    }

    function testCannotTrustedRegisterFromArbitrarySender(
        address trustedSender,
        address arbitrarySender,
        address alice
    ) public {
        vm.assume(arbitrarySender != trustedSender);
        vm.assume(trustedSender != FORWARDER);
        vm.assume(alice != address(0));
        assertEq(nameRegistry.trustedRegisterEnabled(), 1);

        vm.prank(ADMIN);
        nameRegistry.setTrustedSender(trustedSender);

        vm.prank(arbitrarySender);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.trustedRegister(alice, "alice", address(0));
    }

    function testCannotTrustedRegisterWhenPaused(address trustedSender, address alice) public {
        vm.assume(alice != address(0));
        vm.assume(trustedSender != FORWARDER);
        _grant(OPERATOR_ROLE, ADMIN);

        assertEq(nameRegistry.trustedRegisterEnabled(), 1);
        vm.prank(ADMIN);
        nameRegistry.setTrustedSender(trustedSender);

        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(trustedSender);
        vm.expectRevert("Pausable: paused");
        nameRegistry.trustedRegister(alice, "alice", address(0));

        vm.expectRevert(NameRegistry.Registrable.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
    }

    /*//////////////////////////////////////////////////////////////
                               RENEW TESTS
    //////////////////////////////////////////////////////////////*/

    function testRenewSelf(address alice) public {
        // 1. Register alice and fast forward to renewal
        _assumeClean(alice);
        _register(alice);

        vm.warp(JAN1_2023_TS);

        // 2. Alice renews her own username
        vm.expectEmit(true, true, true, true);
        emit Renew(ALICE_TOKEN_ID, JAN1_2024_TS);
        vm.prank(alice);
        nameRegistry.renew{value: 0.01 ether}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testRenewOther(address alice, address bob) public {
        // 1. Register alice and fast forward to renewal
        _assumeClean(bob);
        vm.assume(alice != bob);
        _assumeClean(alice);
        _register(alice);
        vm.warp(JAN1_2023_TS);

        // 2. Bob renews alice's username for her
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Renew(ALICE_TOKEN_ID, JAN1_2024_TS);
        nameRegistry.renew{value: 0.01 ether}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testRenewWithOverpayment(address alice) public {
        _assumeClean(alice);
        _register(alice);
        vm.warp(JAN1_2023_TS);

        // Renew alice's registration, but overpay the amount
        vm.startPrank(alice);
        uint256 balance = alice.balance;
        nameRegistry.renew{value: 0.02 ether}(ALICE_TOKEN_ID);
        vm.stopPrank();

        assertEq(alice.balance, balance - 0.01 ether);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testCannotRenewWithoutPayment(address alice) public {
        _assumeClean(alice);
        _register(alice);
        vm.warp(JAN1_2023_TS);

        // 2. Renewing fails if insufficient funds are provided
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.renew(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    function testCannotRenewIfRegistrable(address alice) public {
        _assumeClean(alice);
        // 1. Fund alice and fast-forward to 2022, when registrations can occur
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.renew{value: 0.01 ether}(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Registrable.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotRenewIfBiddable(address alice) public {
        // 1. Register alice and fast-forward to 2023 when the registration expires
        _assumeClean(alice);
        _register(alice);
        vm.warp(JAN31_2023_TS);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Biddable.selector);
        nameRegistry.renew{value: 0.01 ether}(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    function testCannotRenewIfRegistered(address alice) public {
        // Fast forward to the last second of this year (2022) when the registration is still valid
        _assumeClean(alice);

        _register(alice);
        vm.warp(JAN1_2023_TS - 1);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registered.selector);
        nameRegistry.renew{value: 0.01 ether}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    function testCannotRenewIfPaused(address alice) public {
        _assumeClean(alice);
        _register(alice);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.warp(JAN1_2023_TS);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(alice);
        nameRegistry.renew{value: 0.01 ether}(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    /*//////////////////////////////////////////////////////////////
                                BID TESTS
    //////////////////////////////////////////////////////////////*/

    function testBid(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.deal(bob, 1001 ether);
        vm.warp(JAN31_2023_TS);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.bid{value: 1_000.01 ether}(ALICE_TOKEN_ID, charlie);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), charlie);
    }

    function testBidResetsERC721Approvals(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);

        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 1. Set bob as the approver of alice's token
        vm.prank(alice);
        nameRegistry.approve(bob, ALICE_TOKEN_ID);
        vm.warp(JAN31_2023_TS);

        // 2. Bob bids and succeeds because bid >= premium + fee
        vm.deal(bob, 1001 ether);
        vm.prank(bob);
        nameRegistry.bid{value: 1_000.01 ether}(ALICE_TOKEN_ID, charlie);

        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
    }

    function testBidOverpaymentIsRefunded(address alice, address bob) public {
        _assumeClean(alice);

        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 1. Bob bids and overpays the amount.
        vm.warp(JAN31_2023_TS);
        vm.deal(bob, 1001 ether);
        vm.prank(bob);
        nameRegistry.bid{value: 1001 ether}(ALICE_TOKEN_ID, address(0));

        // 2. Check that bob 's change is returned
        assertEq(bob.balance, 0.990821917808219179 ether);
    }

    function testBidAfterOneStep(address alice, address bob) public {
        // 1. Register alice and fast-forward to 8 hours into the auction
        _assumeClean(alice);

        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.warp(JAN31_2023_TS + 8 hours);

        // 2. Bob bids and fails because bid < price (premium + fee)
        // price = (0.9^1 * 1_000) + 0.00916894977 = 900.009169
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: 900.0091 ether}(ALICE_TOKEN_ID, address(0));

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);

        // 3. Bob bids and succeeds because bid > price
        nameRegistry.bid{value: 900.0092 ether}(ALICE_TOKEN_ID, address(0));
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testBidOnHundredthStep(address alice, address bob) public {
        // 1. Register alice and fast-forward to 800 hours into the auction
        _assumeClean(alice);

        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.warp(JAN31_2023_TS + (8 hours * 100));

        // 2. Bob bids and fails because bid < price (premium + fee)
        // price = (0.9^100 * 1_000) + 0.00826484018 = 0.0348262391
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: 0.0348 ether}(ALICE_TOKEN_ID, address(0));

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);

        // 3. Bob bids and succeeds because bid > price
        nameRegistry.bid{value: 0.0349 ether}(ALICE_TOKEN_ID, address(0));
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testBidOnPenultimateStep(address alice, address bob) public {
        // 1. Register alice and fast-forward to 3056 hours into the auction
        _assumeClean(alice);

        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.warp(JAN31_2023_TS + (8 hours * 382));

        // 2. Bob bids and fails because bid < price (premium + fee)
        // price = (0.9^382 * 1_000) + 0.00568949772 = 0.00568949772 (+ ~ - 3.31e-15)
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: 0.00568949771 ether}(ALICE_TOKEN_ID, address(0));

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);

        // 3. Bob bids and succeeds because bid > price
        nameRegistry.bid{value: 0.005689498772 ether}(ALICE_TOKEN_ID, address(0));
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testBidFlatRate(address alice, address bob) public {
        _assumeClean(bob);
        _assumeClean(alice);

        vm.assume(alice != bob);
        _register(alice);

        vm.warp(JAN31_2023_TS + (8 hours * 383));
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);

        // 2. Bob bids and fails because bid < price (0 + fee) == 0.0056803653
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: 0.0056803652 ether}(ALICE_TOKEN_ID, address(0));

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);

        // 3. Bob bids and succeeds because bid > price (0 + fee)
        nameRegistry.bid{value: 0.0056803653 ether}(ALICE_TOKEN_ID, address(0));
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testCannotBidAfterSuccessfulBid(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 1. Bob bids and succeeds because bid >= premium + fee
        vm.warp(JAN31_2023_TS);
        vm.deal(bob, 1001 ether);
        vm.prank(bob);
        nameRegistry.bid{value: 1_000.01 ether}(ALICE_TOKEN_ID, address(0));

        // 2. Alice bids again and fails because the name is no longer for auction
        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotBiddable.selector);
        nameRegistry.bid(ALICE_TOKEN_ID, charlie);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidWithUnderpayment(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 1. Bob bids and fails because bid < premium + fee
        vm.warp(JAN31_2023_TS);
        vm.deal(bob, 1001 ether);
        vm.startPrank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: 1000 ether}(ALICE_TOKEN_ID, address(0));

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidUnlessBiddable(address alice, address bob) public {
        // 1. Register alice and fast-forward to one second before the auction starts
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 2. Bid during registered state should fail
        vm.startPrank(bob);
        vm.warp(JAN1_2023_TS - 1);
        vm.expectRevert(NameRegistry.NotBiddable.selector);
        nameRegistry.bid(ALICE_TOKEN_ID, address(0));

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);

        // 2. Bid during renewable state should fail
        vm.warp(JAN31_2023_TS - 1);
        vm.expectRevert(NameRegistry.NotBiddable.selector);
        nameRegistry.bid(ALICE_TOKEN_ID, address(0));

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.stopPrank();
    }

    function testBidShouldClearRecovery(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. Register alice and set up a recovery address.
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. Bob requests a recovery of @alice to Charlie
        vm.startPrank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);

        // 3. Bob completes a bid on alice
        vm.warp(JAN31_2023_TS);
        vm.deal(bob, 1001 ether);
        nameRegistry.bid{value: 1001 ether}(ALICE_TOKEN_ID, address(0));
        vm.stopPrank();

        // 4. Assert that the recovery state has been unset
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfInvitable(address bob) public {
        _assumeClean(bob);

        // 1. Bid on @alice when it is not minted and still in trusted registration
        vm.prank(bob);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.bid(ALICE_TOKEN_ID, address(0));

        vm.expectRevert(NameRegistry.Registrable.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotBidIfPaused(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.deal(bob, 1001 ether);
        vm.prank(ADMIN);
        nameRegistry.pause();
        vm.warp(JAN31_2023_TS);

        vm.prank(bob);
        vm.expectRevert("Pausable: paused");
        nameRegistry.bid{value: 1_000.01 ether}(ALICE_TOKEN_ID, charlie);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1); // balanceOf counts expired ids by design
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-721 TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerOfRevertsIfExpired(address alice) public {
        _assumeClean(alice);
        _register(alice);

        vm.warp(JAN31_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.ownerOf(ALICE_TOKEN_ID);
    }

    function testOwnerOfRevertsIfRegistrable() public {
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.ownerOf(ALICE_TOKEN_ID);
    }

    function testTransferFrom(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
    }

    function testTransferFromResetsRecovery(
        address alice,
        address bob,
        address charlie,
        address david
    ) public {
        // 1. Register alice and set up a recovery address.
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != david);
        vm.assume(alice != bob);
        vm.assume(david != address(0));
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. Bob requests a recovery of @alice to Charlie
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);

        // 3. Alice transfers then name to david
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, david, ALICE_TOKEN_ID);
        nameRegistry.transferFrom(alice, david, ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), david);
        assertEq(nameRegistry.balanceOf(david), 1);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testTransferFromCannotTransferExpiredName(address alice, address bob) public {
        // 1. Register alice and set up a recovery address.
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 2. Fast forward to name in renewable state
        vm.startPrank(alice);
        vm.warp(JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);

        // 3. Fast forward to name in expired state
        vm.warp(JAN31_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);
        vm.stopPrank();

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
    }

    function testCannotTransferFromIfPaused(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
    }

    function testTokenUri() public {
        uint256 tokenId = uint256(bytes32("alice"));
        assertEq(nameRegistry.tokenURI(tokenId), "http://www.farcaster.xyz/u/alice.json");

        // Test with min length name
        uint256 tokenIdMin = uint256(bytes32("a"));
        assertEq(nameRegistry.tokenURI(tokenIdMin), "http://www.farcaster.xyz/u/a.json");

        // Test with max length name
        uint256 tokenIdMax = uint256(bytes32("alicenwonderland"));
        assertEq(nameRegistry.tokenURI(tokenIdMax), "http://www.farcaster.xyz/u/alicenwonderland.json");
    }

    function testCannotGetTokenUriForInvalidName() public {
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.tokenURI(uint256(bytes32("alicenWonderland")));
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeRecoveryAddress(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 1. alice sets bob as her recovery address
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(ALICE_TOKEN_ID, alice);

        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), alice);

        // 2. alice sets charlie as her recovery address
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(ALICE_TOKEN_ID, charlie);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, charlie);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), charlie);

        vm.stopPrank();
    }

    function testCannotChangeRecoveryAddressUnlessOwner(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, charlie);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotChangeRecoveryAddressIfRenewable(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.warp(JAN1_2023_TS);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotChangeRecoveryAddressIfBiddable(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.warp(JAN31_2023_TS);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotChangeRecoveryAddressIfRegistrable(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);

        vm.expectRevert(NameRegistry.Registrable.selector);
        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(BOB_TOKEN_ID, bob);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotChangeRecoveryAddressIfPaused(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testChangeRecoveryAddressResetsRecovery(
        address alice,
        address bob,
        address charlie,
        address david
    ) public {
        // 1. alice registers @alice and sets bob as her recovery
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != david);
        vm.assume(alice != bob);
        vm.assume(david != address(0));
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of @alice to charlie and then alice changes the recovery address
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);
        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, david);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), david);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery(
        address alice,
        address bob,
        address charlie,
        address david
    ) public {
        // 1. alice registers id 1 and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != david);
        vm.assume(alice != bob);
        vm.assume(david != address(0));
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(alice, charlie, ALICE_TOKEN_ID);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), charlie);

        // 3. bob then requests another recovery to david
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, david);

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), david);
    }

    function testCannotRequestRecoveryToZeroAddr(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 1. bob requests a recovery of alice's id to 0x0
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InvalidRecovery.selector);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, address(0));

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRequestRecoveryUnlessAuthorized(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        // 1. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRequestRecoveryIfRegistrable(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));

        // 1. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRequestRecoveryIfPaused(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice, sets bob as her recovery address and the contract is paused
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // 2. bob requests a recovery which fails
        vm.prank(bob);
        vm.expectRevert("Pausable: paused");
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteRecovery(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        // 3. after escrow period, bob completes the recovery to charlie
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, ALICE_TOKEN_ID);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), charlie);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testRecoveryCompletionResetsERC721Approvals(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address and approver
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.startPrank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);
        nameRegistry.approve(bob, ALICE_TOKEN_ID);
        vm.stopPrank();

        // 2. bob requests and completes a recovery to charlie
        vm.startPrank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);
        vm.warp(block.timestamp + ESCROW_PERIOD);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);
        vm.stopPrank();

        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
    }

    function testCannotCompleteRecoveryIfUnauthorized(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(bob != charlie);
        vm.assume(charlie != address(0));
        _register(alice);

        // warp to ensure that block.timestamp is not zero so we can assert the reset of the recovery clock
        vm.warp(100);
        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        vm.prank(charlie);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
    }

    function testCannotCompleteRecoveryIfStartedByPrevious(
        address alice,
        address bob,
        address charlie,
        address david
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _assumeClean(david);
        vm.assume(alice != bob);
        vm.assume(alice != charlie);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 1. bob requests a recovery of @alice to charlie and then alice changes the recovery to david
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);
        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, david);

        // 2. after escrow period, david attempts to complete recovery which fails
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.prank(david);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(charlie), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), david);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotCompleteRecoveryIfNotStarted(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 1. bob calls recovery complete on alice's id, which fails
        vm.prank(bob);
        vm.warp(block.number + ESCROW_PERIOD);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotCompleteRecoveryWhenInEscrow(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.startPrank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        // 3. before escrow period, bob completes the recovery to charlie
        vm.expectRevert(NameRegistry.Escrow.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        vm.stopPrank();
    }

    function testCannotCompleteRecoveryIfExpired(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of @alice to charlie
        uint256 requestTs = block.timestamp;
        vm.startPrank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        // 3. during the renewal period, bob attempts to recover to charlie
        vm.warp(JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);

        // 3. during expiry, bob attempts to recover to charlie
        vm.warp(JAN31_2023_TS);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        vm.stopPrank();
    }

    function testCannotCompleteRecoveryIfPaused(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address, and @bob requests a recovery to recovery.
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);
        uint256 recoveryTs = block.timestamp;

        // 2. the contract is then paused by the ADMIN and we warp past the escrow period
        vm.prank(ADMIN);
        nameRegistry.pause();
        vm.warp(recoveryTs + ESCROW_PERIOD);

        // 3. bob attempts to complete the recovery, which fails
        vm.prank(bob);
        vm.expectRevert("Pausable: paused");
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), recoveryTs);
    }

    /*//////////////////////////////////////////////////////////////
                          CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        // 3. alice cancels the recovery
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit CancelRecovery(ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        vm.prank(bob);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
    }

    function testCancelRecoveryFromRecoveryAddress(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.startPrank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        // 3. bob cancels the recovery
        vm.expectEmit(true, false, false, false);
        emit CancelRecovery(ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        vm.stopPrank();
    }

    function testCancelRecoveryIfPaused(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address and @bob requests a recovery, after which
        // the ADMIN pauses the contract
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // 2. alice cancels the recovery, which succeeds
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit CancelRecovery(ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotCancelRecoveryIfNotStarted(address alice, address bob) public {
        // 1. alice registers @alice and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.startPrank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. alice cancels the recovery which fails
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotCancelRecoveryIfUnauthorized(
        address alice,
        address bob,
        address charlie
    ) public {
        // 1. alice registers @alice and sets bob as her recovery address
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        vm.assume(charlie != bob);
        vm.assume(charlie != alice);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        // 3. charlie cancels the recovery which fails
        vm.prank(charlie);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                             MODERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testReclaimRegisteredNames(address alice) public {
        _assumeClean(alice);
        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);

        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, vault, ALICE_TOKEN_ID);
        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), vault);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testReclaimRenewableNames(address alice) public {
        _assumeClean(alice);
        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);

        vm.warp(JAN1_2023_TS);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, vault, ALICE_TOKEN_ID);
        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), vault);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testReclaimBiddableNames(address alice) public {
        _assumeClean(alice);
        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);

        vm.warp(JAN31_2023_TS);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, vault, ALICE_TOKEN_ID);
        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), vault);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
    }

    function testReclaimResetsERC721Approvals(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);

        vm.prank(alice);
        nameRegistry.approve(bob, ALICE_TOKEN_ID);

        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
    }

    function testCannotReclaimUnlessMinted() public {
        _grant(MODERATOR_ROLE, ADMIN);
        vm.expectRevert(NameRegistry.Registrable.selector);
        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);
    }

    function testReclaimResetsRecoveryState(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(charlie != address(0));
        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, bob);

        vm.prank(bob);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, alice, charlie);

        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), vault);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testReclaimWhenPaused(address alice) public {
        _assumeClean(alice);
        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(ADMIN);
        vm.expectRevert("Pausable: paused");
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    function testCannotReclaimUnlessModerator(address alice) public {
        _assumeClean(alice);
        _register(alice);

        vm.prank(ADMIN);
        vm.expectRevert(NameRegistry.NotModerator.selector);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetTrustedSender(address alice) public {
        vm.assume(alice != nameRegistry.trustedSender());

        vm.prank(ADMIN);
        nameRegistry.setTrustedSender(alice);
        assertEq(nameRegistry.trustedSender(), alice);
    }

    function testCannotSetTrustedSenderUnlessOwner(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        assertEq(nameRegistry.trustedSender(), address(0));

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOwner.selector);
        nameRegistry.setTrustedSender(bob);
        assertEq(nameRegistry.trustedSender(), address(0));
    }

    function testDisableTrustedSender() public {
        assertEq(nameRegistry.trustedRegisterEnabled(), 1);

        vm.prank(ADMIN);
        nameRegistry.disableTrustedRegister();
        assertEq(nameRegistry.trustedRegisterEnabled(), 0);
    }

    function testCannotDisableTrustedSenderUnlessOwner(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        assertEq(nameRegistry.trustedRegisterEnabled(), 1);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOwner.selector);
        nameRegistry.disableTrustedRegister();
        assertEq(nameRegistry.trustedRegisterEnabled(), 1);
    }

    function testChangeVault(address alice, address bob) public {
        vm.assume(alice != nameRegistry.trustedSender());
        assertEq(nameRegistry.vault(), vault);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ChangeVault(bob);
        nameRegistry.changeVault(bob);
        assertEq(nameRegistry.vault(), bob);
    }

    function testCannotChangeVaultUnlessOwner(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.vault(), vault);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOwner.selector);
        nameRegistry.changeVault(bob);
        assertEq(nameRegistry.vault(), vault);
    }

    /*//////////////////////////////////////////////////////////////
                           DEFAULT ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testGrantOwnerRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);
    }

    function testRevokeOwnerRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);

        vm.prank(defaultAdmin);
        nameRegistry.revokeRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);
    }

    function testCannotGrantOwnerRoleUnlessDefaultAdmin(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, bob), false);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
        nameRegistry.grantRole(ADMIN_ROLE, bob);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, bob), false);
    }

    /*//////////////////////////////////////////////////////////////
                             TREASURER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetFee() public {
        _grant(TREASURER_ROLE, ADMIN);
        assertEq(nameRegistry.fee(), 0.01 ether);

        vm.prank(ADMIN);
        nameRegistry.setFee(0.02 ether);

        assertEq(nameRegistry.fee(), 0.02 ether);
    }

    function testCannotSetFeeUnlessTreasurer(address alice2) public {
        vm.assume(alice2 != FORWARDER);

        vm.prank(alice2);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.setFee(0.02 ether);
    }

    function testWithdrawFunds(address alice) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);

        vm.prank(alice);
        nameRegistry.withdraw(1 ether);
        assertEq(address(nameRegistry).balance, 0 ether);
        assertEq(vault.balance, 1 ether);
    }

    function testCannotWithdrawUnlessTreasurer(address alice) public {
        _assumeClean(alice);
        vm.deal(address(nameRegistry), 1 ether);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.withdraw(0.01 ether);
        assertEq(address(nameRegistry).balance, 1 ether);
    }

    function testCannotWithdrawInvalidAmount(address alice) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.WithdrawTooMuch.selector);
        nameRegistry.withdraw(1.01 ether);
        assertEq(address(nameRegistry).balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             OPERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotPauseUnlessOperator(address alice2) public {
        vm.assume(alice2 != FORWARDER);

        vm.prank(alice2);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.pause();
    }

    function testCannotUnpauseUnlessOperator(address alice2) public {
        vm.assume(alice2 != FORWARDER);

        vm.prank(alice2);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          YEARLY PAYMENTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCurrYear() public {
        // Incorrectly returns 2021 for any date before 2021
        vm.warp(1607558400); // GMT Thursday, December 10, 2020 0:00:00
        assertEq(nameRegistry.currYear(), 2021);

        // Works correctly for known year range [2021 - 2072]
        vm.warp(1640095200); // GMT Tuesday, December 21, 2021 14:00:00
        assertEq(nameRegistry.currYear(), 2021);

        vm.warp(1670889599); // GMT Monday, December 12, 2022 23:59:59
        assertEq(nameRegistry.currYear(), 2022);

        // Does not work after 2072
        vm.warp(3250454400); // GMT Friday, January 1, 2073 0:00:00
        vm.expectRevert(NameRegistry.InvalidTime.selector);
        assertEq(nameRegistry.currYear(), 0);
    }

    function testCurrYearFee() public {
        _grant(TREASURER_ROLE, ADMIN);
        // fee = 0.1 ether
        vm.warp(1672531200); // GMT Friday, January 1, 2023 0:00:00
        assertEq(nameRegistry.currYearFee(), 0.01 ether);

        vm.warp(1688256000); // GMT Sunday, July 2, 2023 0:00:00
        assertEq(nameRegistry.currYearFee(), 0.005013698630136986 ether);

        vm.warp(1704023999); // GMT Friday, Dec 31, 2023 11:59:59
        assertEq(nameRegistry.currYearFee(), 0.000013698947234906 ether);

        // fee = 0.2 ether
        vm.prank(ADMIN);
        nameRegistry.setFee(0.02 ether);

        vm.warp(1672531200); // GMT Friday, January 1, 2023 0:00:00
        assertEq(nameRegistry.currYearFee(), 0.02 ether);

        vm.warp(1688256000); // GMT Sunday, July 2, 2023 0:00:00
        assertEq(nameRegistry.currYearFee(), 0.010027397260273972 ether);

        vm.warp(1704023999); // GMT Friday, Dec 31, 2023 11:59:59
        assertEq(nameRegistry.currYearFee(), 0.000027397894469812 ether);

        // fee = 0 ether
        vm.prank(ADMIN);
        nameRegistry.setFee(0 ether);

        vm.warp(1672531200); // GMT Friday, January 1, 2023 0:00:00
        assertEq(nameRegistry.currYearFee(), 0);

        vm.warp(1688256000); // GMT Sunday, July 2, 2023 0:00:00
        assertEq(nameRegistry.currYearFee(), 0);

        vm.warp(1704023999); // GMT Friday, Dec 31, 2023 11:59:59
        assertEq(nameRegistry.currYearFee(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    // Given an address, funds it with ETH, warps to a registration period and registers the username @alice
    function _register(address alice) internal {
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        vm.startPrank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, "secret");
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + COMMIT_PERIOD);

        nameRegistry.register{value: nameRegistry.fee()}("alice", alice, "secret", address(0));
        vm.stopPrank();
    }

    // Ensures that a given fuzzed address does not match known contracts
    function _assumeClean(address a) internal {
        for (uint256 i = 0; i < knownContracts.length; i++) {
            vm.assume(a != knownContracts[i]);
        }

        vm.assume(a > PRECOMPILE_CONTRACTS);
        vm.assume(a != ADMIN);
    }

    function _disableTrusted() internal {
        vm.prank(ADMIN);
        nameRegistry.disableTrustedRegister();
    }

    function _grant(bytes32 role, address target) internal {
        vm.prank(defaultAdmin);
        nameRegistry.grantRole(role, target);
    }
}
