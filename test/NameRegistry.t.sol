// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import "forge-std/Test.sol";

import "./TestConstants.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

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
    event Invite(uint256 indexed inviterId, uint256 indexed inviteeId, bytes16 indexed fname);
    event ChangeRecoveryAddress(uint256 indexed tokenId, address indexed recovery);
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed tokenId);
    event CancelRecovery(address indexed by, uint256 indexed tokenId);
    event ChangeTrustedCaller(address indexed trustedCaller);
    event DisableTrustedOnly();
    event ChangeVault(address indexed vault);
    event ChangePool(address indexed pool);
    event ChangeFee(uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address defaultAdmin = address(this);

    // Known contracts that must not be made to call other contracts in tests
    address[] knownContracts = [
        address(0xCe71065D4017F316EC606Fe4422e11eB2c47c246), // FuzzerDict
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C), // CREATE2 Factory
        address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), // address(this)
        address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A), // FORWARDER
        address(0x185a4dc360CE69bDCceE33b3784B0282f7961aea), // ???
        address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D), // ???
        address(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f), // ???
        address(0x2e234DAe75C793f67A35089C9d99245E1C58470b), // ???
        address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) // ???
    ];

    // Address of the last precompile contract
    address constant MAX_PRECOMPILE = address(9);

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);

    uint256 constant COMMIT_REVEAL_DELAY = 60 seconds;
    uint256 constant COMMIT_REPLAY_DELAY = 10 minutes;
    uint256 constant ESCROW_PERIOD = 3 days;
    uint256 constant REGISTRATION_PERIOD = 365 days;
    uint256 constant RENEWAL_PERIOD = 30 days;

    uint256 constant BID_START = 1_000 ether;
    uint256 constant FEE = 0.01 ether;

    // Max value to use when fuzzing msg.value amounts, to prevent impractical overflow failures
    uint256 constant AMOUNT_FUZZ_MAX = 1_000_000_000_000 ether;

    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT

    uint256 constant ALICE_TOKEN_ID = uint256(bytes32("alice"));
    uint256 constant BOB_TOKEN_ID = uint256(bytes32("bob"));
    uint256 constant CAROL_TOKEN_ID = uint256(bytes32("carol"));
    uint256 constant DAN_TOKEN_ID = uint256(bytes32("dan"));

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    bytes16[] fnames = [bytes16("alice"), bytes16("bob"), bytes16("carol"), bytes16("dan")];

    uint256[] tokenIds = [ALICE_TOKEN_ID, BOB_TOKEN_ID, CAROL_TOKEN_ID, DAN_TOKEN_ID];

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        nameRegistryImpl = new NameRegistry(FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);
    }

    /*//////////////////////////////////////////////////////////////
                              COMMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGenerateCommit() public {
        address alice = address(0x123);
        address recovery = address(0x456);

        // alphabetic name
        bytes32 commit1 = nameRegistry.generateCommit("alice", alice, "secret", recovery);
        assertEq(commit1, 0xf6d11924ab4b4f89882cb4feed6a4365d22f4d0344d4b58abe27e6886b83b811);

        // 1-char name
        bytes32 commit2 = nameRegistry.generateCommit("1", alice, "secret", recovery);
        assertEq(commit2, 0xc2c738c5b10e7bf31692bc6603b035245be099b35ace27ba21f2ce793852aaaa);

        // 16-char alphabetic
        bytes32 commit3 = nameRegistry.generateCommit("alicenwonderland", alice, "secret", recovery);
        assertEq(commit3, 0xc52dbd957d10771393523f943e365d409742486a8ec4d5d11a90f725bc3b6ec3);

        // 16-char alphanumeric name
        bytes32 commit4 = nameRegistry.generateCommit("alice0wonderland", alice, "secret", recovery);
        assertEq(commit4, 0xf3291f3f5ce66f7e375ae3d117401bb1581787b8a82185920bf4ec5914120520);

        // 16-char alphanumeric hyphenated name
        bytes32 commit5 = nameRegistry.generateCommit("al1c3-w0nderl4nd", alice, "secret", recovery);
        assertEq(commit5, 0x8c66607f500ae32d56494a3415cd1e630d35ac72da15cda0e33a869dd7b747dc);
    }

    function testCannotGenerateCommitWithInvalidName(address alice, bytes32 secret, address recovery) public {
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("Alice", alice, secret, recovery);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a/lice", alice, secret, recovery);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a:lice", alice, secret, recovery);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a`ice", alice, secret, recovery);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a{ice", alice, secret, recovery);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("-alice", alice, secret, recovery);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(" alice", alice, secret, recovery);

        bytes16 blankName = 0x00000000000000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(blankName, alice, secret, recovery);

        // Should reject "a�ice", where � == 129 which is an invalid ASCII character
        bytes16 nameWithInvalidAsciiChar = 0x61816963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithInvalidAsciiChar, alice, secret, recovery);

        // Should reject "a�ice", where � == NULL
        bytes16 nameWithEmptyByte = 0x61006963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithEmptyByte, alice, secret, recovery);

        // Should reject "�lice", where � == NULL
        bytes16 nameWithStartingEmptyByte = 0x006c6963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithStartingEmptyByte, alice, secret, recovery);
    }

    function testMakeCommit(address alice, bytes32 secret, address recovery) public {
        _disableTrusted();
        vm.warp(JAN1_2023_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);

        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);
    }

    function testMakeCommitAfterReplayDelay(address alice, bytes32 secret, address recovery, uint256 delay) public {
        _disableTrusted();
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay > COMMIT_REPLAY_DELAY);
        vm.warp(JAN1_2023_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);

        // Make the first commit
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);

        // Make the second commit after the replay delay
        vm.warp(block.timestamp + delay);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);
    }

    function testCannotMakeCommitBeforeReplayDelay(
        address alice,
        bytes32 secret,
        address recovery,
        uint256 delay
    ) public {
        _disableTrusted();
        delay = delay % COMMIT_REPLAY_DELAY; // fuzz between 0 and (COMMIT_REPLAY_DELAY - 1)
        vm.warp(JAN1_2023_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);

        // Make the first commit
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        uint256 firstCommitTs = block.timestamp;
        assertEq(nameRegistry.timestampOf(commitHash), firstCommitTs);

        // Make the second commit before the replay delay
        vm.warp(block.timestamp + delay);
        vm.expectRevert(NameRegistry.CommitReplay.selector);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), firstCommitTs);
    }

    function testCannotMakeCommitDuringTrustedRegister(address alice, bytes32 secret, address recovery) public {
        vm.warp(JAN1_2023_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Invitable.selector);
        nameRegistry.makeCommit(commitHash);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the recovery address of a fname.
     *
     * @param tokenId The uint256 representation of the fname
     * @return recovery The address which can recover the fname
     */

    function _recovery(uint256 tokenId) internal view returns (address recovery) {
        (recovery,) = nameRegistry.registrationMetadataOf(tokenId);
    }

    /**
     * @notice Get the expiration time of a fname.
     *
     * @param tokenId The uint256 representation of the fname
     * @return expiryTs The timestamp when the fname expires
     */
    function expiry(uint256 tokenId) internal view returns (uint256 expiryTs) {
        (, expiryTs) = nameRegistry.registrationMetadataOf(tokenId);
    }

    /**
     * @notice Get the recovery destination of a fname.
     *
     * @param tokenId The uint256 representation of the fname
     * @return _recoveryDestination The destination address of the most recent recovery attempt.
     */
    function recoveryDestination(uint256 tokenId) internal view returns (address _recoveryDestination) {
        (_recoveryDestination,) = nameRegistry.recoveryMetadataOf(tokenId);
    }

    /**
     * @notice Get the recovery clock of a fname.
     *
     * @param tokenId The uint256 representation of the fname
     * @return recoveryTs The timestamp of the recovery attempt or zero if there is no active recovery.
     */
    function _recoveryTs(uint256 tokenId) internal view returns (uint256 recoveryTs) {
        (, recoveryTs) = nameRegistry.recoveryMetadataOf(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister(
        address alice,
        address bob,
        address recovery,
        bytes32 secret,
        uint256 amount,
        uint256 delay
    ) public {
        vm.assume(bob != address(0));
        _assumeClean(alice);
        _disableTrusted();
        vm.warp(JAN1_2023_TS);

        vm.assume(amount >= FEE);
        vm.deal(alice, amount);

        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= COMMIT_REPLAY_DELAY);

        vm.prank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("bob", bob, secret, recovery);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + delay);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), bob, BOB_TOKEN_ID);
        vm.prank(alice);
        nameRegistry.register{value: amount}("bob", bob, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), 0);
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(BOB_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(_recovery(BOB_TOKEN_ID), recovery);
        assertEq(alice.balance, amount - nameRegistry.fee());
    }

    function testRegisterWorksWhenAlreadyOwningAName(
        address alice,
        address recovery,
        bytes32 secret,
        uint256 delay_bob,
        uint256 delay_alice
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.warp(JAN1_2023_TS);

        delay_alice = delay_alice % FUZZ_TIME_PERIOD;
        delay_bob = delay_bob % FUZZ_TIME_PERIOD;
        vm.assume(delay_alice >= COMMIT_REPLAY_DELAY);
        vm.assume(delay_bob >= COMMIT_REPLAY_DELAY);

        // Register @alice to alice
        vm.startPrank(alice);
        bytes32 commitHashAlice = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(commitHashAlice);
        vm.warp(block.timestamp + delay_alice);
        uint256 aliceRegister = block.timestamp;
        nameRegistry.register{value: nameRegistry.fee()}("alice", alice, secret, recovery);

        // make this assertion before Alice's registration expires
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);

        // Register @bob to alice
        bytes32 commitHashBob = nameRegistry.generateCommit("bob", alice, secret, recovery);
        nameRegistry.makeCommit(commitHashBob);
        vm.warp(block.timestamp + delay_bob);
        uint256 bobRegister = block.timestamp;
        nameRegistry.register{value: FEE}("bob", alice, secret, recovery);
        vm.stopPrank();

        assertEq(nameRegistry.timestampOf(commitHashAlice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), aliceRegister + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);

        assertEq(nameRegistry.timestampOf(commitHashBob), 0);
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), alice);
        assertEq(expiry(BOB_TOKEN_ID), bobRegister + REGISTRATION_PERIOD);
        assertEq(_recovery(BOB_TOKEN_ID), recovery);

        assertEq(nameRegistry.balanceOf(alice), 2);
    }

    // TODO: this is an integration test, and should be moved out to a separate file
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
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotRegisterTheSameNameAgain(
        address alice,
        address bob,
        bytes32 secret,
        address recovery,
        uint256 delay
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.warp(JAN1_2023_TS);

        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= COMMIT_REPLAY_DELAY);

        // Register @alice to alice
        bytes32 aliceCommitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(aliceCommitHash);
        vm.warp(block.timestamp + delay);

        vm.prank(alice);
        nameRegistry.register{value: FEE}("alice", alice, secret, recovery);
        uint256 registerTs = block.timestamp;
        assertEq(nameRegistry.timestampOf(aliceCommitHash), 0);

        // Register @alice to bob which should fail
        bytes32 bobCommitHash = nameRegistry.generateCommit("alice", bob, secret, recovery);
        nameRegistry.makeCommit(bobCommitHash);
        uint256 commitTs = block.timestamp;

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.prank(bob);
        vm.expectRevert("ERC721: token already minted");
        nameRegistry.register{value: FEE}("alice", bob, secret, recovery);

        assertEq(nameRegistry.timestampOf(bobCommitHash), commitTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(expiry(ALICE_TOKEN_ID), registerTs + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotRegisterExpiredName(address alice, address bob, bytes32 secret, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.warp(JAN1_2023_TS);

        // Register @alice to alice
        bytes32 aliceCommitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(aliceCommitHash);
        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);

        vm.prank(alice);
        nameRegistry.register{value: FEE}("alice", alice, secret, recovery);
        uint256 registerTs = block.timestamp;
        assertEq(nameRegistry.timestampOf(aliceCommitHash), 0);

        // Fast forward to when @alice is renewable and register @alice to bob
        vm.warp(registerTs + REGISTRATION_PERIOD);
        bytes32 bobCommitHash = nameRegistry.generateCommit("alice", bob, secret, recovery);
        nameRegistry.makeCommit(bobCommitHash);
        uint256 commitTs = block.timestamp;

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.prank(bob);
        vm.expectRevert("ERC721: token already minted");
        nameRegistry.register{value: FEE}("alice", bob, secret, recovery);

        assertEq(expiry(ALICE_TOKEN_ID), registerTs + REGISTRATION_PERIOD);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.timestampOf(bobCommitHash), commitTs);

        // Fast forward to when @alice is biddable and register @alice to bob
        vm.warp(block.timestamp + RENEWAL_PERIOD);
        nameRegistry.makeCommit(bobCommitHash);
        commitTs = block.timestamp;

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.prank(bob);
        vm.expectRevert("ERC721: token already minted");
        nameRegistry.register{value: FEE}("alice", bob, secret, recovery);

        assertEq(expiry(ALICE_TOKEN_ID), registerTs + REGISTRATION_PERIOD);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.timestampOf(bobCommitHash), commitTs);
    }

    function testCannotRegisterWithoutPayment(address alice, bytes32 secret, address recovery) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.warp(JAN1_2023_TS);

        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.prank(alice);
        uint256 balance = alice.balance;
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.register{value: 0.0001 ether}("alice", alice, secret, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(alice.balance, balance);
    }

    function testCannotRegisterWithoutCommit(address alice, address bob, bytes32 secret, address recovery) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.assume(bob != address(0));
        vm.deal(alice, 1 ether);
        vm.warp(JAN1_2023_TS);

        bytes16 username = "bob";
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: FEE}(username, bob, secret, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(BOB_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidCommitSecret(
        address alice,
        address bob,
        bytes32 secret,
        bytes32 incorrectSecret,
        address recovery
    ) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        vm.assume(secret != incorrectSecret);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(JAN1_2023_TS);

        bytes16 username = "bob";
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret, recovery);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.prank(alice);
        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: FEE}(username, bob, incorrectSecret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(BOB_TOKEN_ID), 0);
        assertEq(_recovery(BOB_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidCommitAddress(
        address alice,
        address bob,
        bytes32 secret,
        address incorrectOwner,
        address recovery
    ) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        vm.assume(incorrectOwner != address(0));
        vm.assume(bob != incorrectOwner);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(JAN1_2023_TS);

        bytes16 username = "bob";
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret, recovery);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: FEE}(username, incorrectOwner, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(incorrectOwner), 0);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(BOB_TOKEN_ID), 0);
        assertEq(_recovery(BOB_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidCommitName(
        address alice,
        address bob,
        bytes32 secret,
        address recovery
    ) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(JAN1_2023_TS);

        bytes16 username = "bob";
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret, recovery);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        bytes16 incorrectUsername = "alice";
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.prank(alice);
        nameRegistry.register{value: FEE}(incorrectUsername, bob, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(expiry(BOB_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(BOB_TOKEN_ID), address(0));
    }

    function testCannotRegisterBeforeDelay(address alice, bytes32 secret, address recovery) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 10_000 ether);
        vm.warp(JAN1_2023_TS);

        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY - 1);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: FEE}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidName(address alice, bytes32 secret, address recovery) public {
        _assumeClean(alice);
        _disableTrusted();
        bytes16 incorrectUsername = "al{ce";
        uint256 incorrectTokenId = uint256(bytes32(incorrectUsername));
        vm.warp(JAN1_2023_TS);

        uint256 commitTs = block.timestamp;
        bytes32 invalidCommit = keccak256(abi.encode(incorrectUsername, alice, secret));
        nameRegistry.makeCommit(invalidCommit);

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.register{value: FEE}(incorrectUsername, alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(invalidCommit), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(incorrectTokenId), address(0));
        assertEq(expiry(incorrectTokenId), 0);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(_recovery(incorrectTokenId), address(0));
    }

    function testCannotRegisterWhenPaused(address alice, address recovery, bytes32 secret) public {
        _assumeClean(alice);
        _disableTrusted();
        _grant(OPERATOR_ROLE, ADMIN);

        // 1. Make the commitment to register @alice
        vm.deal(alice, 1 ether);
        vm.warp(JAN1_2023_TS);
        vm.prank(alice);
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(commitHash);

        // 2. Pause the contract and try to register the name alice
        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.prank(ADMIN);
        nameRegistry.pause();
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.register{value: FEE}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterFromNonPayableIfOverpaying(address alice, address recovery, bytes32 secret) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.warp(JAN1_2023_TS);

        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);

        // call register() from address(this) which is non-payable
        // overpay by 1 wei to return funds which causes the revert
        vm.expectRevert(NameRegistry.CallFailed.selector);
        nameRegistry.register{value: FEE + 1 wei}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterToZeroAddress(address alice, address recovery, bytes32 secret) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.warp(JAN1_2023_TS);

        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", address(0), secret, recovery);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);
        vm.expectRevert("ERC721: mint to the zero address");
        vm.prank(alice);
        nameRegistry.register{value: FEE}("alice", address(0), secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         REGISTER TRUSTED TESTS
    //////////////////////////////////////////////////////////////*/

    function testTrustedRegister(
        address trustedCaller,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2023_TS);
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, ALICE_TOKEN_ID);
        vm.expectEmit(true, true, true, true);
        emit Invite(inviter, invitee, "alice");
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTrustedRegisterWhenDisabled(
        address trustedCaller,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2023_TS);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.prank(trustedCaller);
        vm.expectRevert(NameRegistry.NotInvitable.selector);
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterNameTwice(
        address trustedCaller,
        address alice,
        address recovery,
        address recovery2,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.assume(recovery != recovery2);
        vm.warp(JAN1_2023_TS);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(trustedCaller);
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        vm.prank(trustedCaller);
        vm.expectRevert("ERC721: token already minted");
        nameRegistry.trustedRegister("alice", alice, recovery2, inviter, invitee);

        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTrustedRegisterFromArbitrarySender(
        address trustedCaller,
        address arbitrarySender,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.assume(arbitrarySender != trustedCaller);
        assertEq(nameRegistry.trustedOnly(), 1);
        vm.warp(JAN1_2023_TS);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(arbitrarySender);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterWhenPaused(
        address trustedCaller,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2023_TS);

        assertEq(nameRegistry.trustedOnly(), 1);
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(trustedCaller);
        vm.expectRevert("Pausable: paused");
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterToZeroAddress(
        address trustedCaller,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2023_TS);

        assertEq(nameRegistry.trustedOnly(), 1);
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        vm.expectRevert("ERC721: mint to the zero address");
        nameRegistry.trustedRegister("alice", address(0), recovery, inviter, invitee);

        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterWithInvalidName(
        address alice,
        address trustedCaller,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2023_TS);

        assertEq(nameRegistry.trustedOnly(), 1);
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.trustedRegister("al}ce", alice, recovery, inviter, invitee);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                               RENEW TESTS
    //////////////////////////////////////////////////////////////*/

    function testRenew(address alice, address bob, uint256 amount, uint256 timestamp) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _register(alice);
        // TODO: Report foundry bug when setting the max to anything higher
        // vm.assume(amount >= FEE && amount < (type(uint256).max - 3 wei));
        amount = (amount % AMOUNT_FUZZ_MAX) + FEE;

        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        timestamp = (timestamp % (RENEWAL_PERIOD)) + renewableTs;
        uint256 expectedExpiryTs = timestamp + REGISTRATION_PERIOD;

        vm.warp(timestamp);
        vm.deal(bob, amount);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Renew(ALICE_TOKEN_ID, expectedExpiryTs);
        nameRegistry.renew{value: amount}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(expiry(ALICE_TOKEN_ID), expectedExpiryTs);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(bob.balance, amount - FEE);
    }

    function testCannotRenewWithoutPayment(address alice, uint256 amount) public {
        _assumeClean(alice);
        _register(alice);
        vm.warp(block.timestamp + REGISTRATION_PERIOD);

        // Ensure that amount is always less than the fee
        amount = (amount % FEE);
        vm.deal(alice, amount);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.renew{value: amount}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(alice.balance, amount);
    }

    function testCannotRenewIfInvitable(address alice) public {
        _assumeClean(alice);
        vm.deal(alice, 1 ether);
        vm.warp(JAN1_2023_TS);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfRegistrable(address alice) public {
        _assumeClean(alice);
        vm.deal(alice, 1 ether);

        vm.warp(JAN1_2023_TS);
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfBiddable(address alice) public {
        _assumeClean(alice);
        _register(alice);
        uint256 registerTs = block.timestamp;
        uint256 renewableTs = registerTs + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        vm.warp(biddableTs);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotRenewable.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfRegistered(address alice) public {
        _assumeClean(alice);
        _register(alice);
        uint256 registerTs = block.timestamp;

        // Fast forward to the last second of 2022 when the registration is still valid
        vm.warp(registerTs + REGISTRATION_PERIOD - 1);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registered.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(expiry(ALICE_TOKEN_ID), registerTs + REGISTRATION_PERIOD);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfPaused(address alice) public {
        _assumeClean(alice);
        _register(alice);
        vm.warp(block.timestamp + REGISTRATION_PERIOD);

        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(alice);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewFromNonPayableIfOverpaying(address alice) public {
        _assumeClean(alice);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        vm.warp(renewableTs);

        vm.expectRevert(NameRegistry.CallFailed.selector);
        // call register() from address(this) which is non-payable
        // overpay by 1 wei to return funds which causes the revert
        nameRegistry.renew{value: FEE + 1 wei}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                BID TESTS
    //////////////////////////////////////////////////////////////*/

    function testBid(
        address alice,
        address bob,
        address charlie,
        address recovery1,
        address recovery2,
        uint256 amount
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _register(alice);
        vm.assume(alice != charlie);
        vm.assume(charlie != address(0));
        amount = amount % AMOUNT_FUZZ_MAX;
        uint256 biddableTs = block.timestamp + REGISTRATION_PERIOD + RENEWAL_PERIOD;

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery1);

        vm.warp(biddableTs);
        uint256 winningBid = BID_START + nameRegistry.fee();
        vm.assume(amount >= (winningBid) && amount < (type(uint256).max - 3 wei));
        vm.deal(bob, amount);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, ALICE_TOKEN_ID);
        nameRegistry.bid{value: amount}(charlie, ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), charlie);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(charlie), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery2);
        assertEq(bob.balance, amount - (winningBid));
    }

    function testBidResetsERC721Approvals(address alice, address bob, address charlie) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        uint256 biddableTs = block.timestamp + REGISTRATION_PERIOD + RENEWAL_PERIOD;

        // 1. Set bob as the approver of alice's token
        vm.prank(alice);
        nameRegistry.approve(bob, ALICE_TOKEN_ID);
        vm.warp(biddableTs);

        // 2. Bob bids and succeeds because bid >= premium + fee
        vm.deal(bob, 1001 ether);
        vm.prank(bob);
        nameRegistry.bid{value: 1_000.01 ether}(bob, ALICE_TOKEN_ID, charlie);

        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
    }

    function testBidAfterOneStep(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1000 ether);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        // After 1 step, we expect the bid premium to be 900.000000000000606000 after errors
        vm.warp(biddableTs + 8 hours);
        uint256 bidPremium = 900.000000000000606 ether;
        uint256 bidPrice = bidPremium + nameRegistry.fee();

        // Bid below the price and fail
        vm.startPrank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));

        // Bid above the price and succeed
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testBidOnHundredthStep(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1 ether);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        // After 100 steps, we expect the bid premium to be 0.026561398887589000 after errors
        vm.warp(biddableTs + (8 hours * 100));
        uint256 bidPremium = 0.026561398887589 ether;
        uint256 bidPrice = bidPremium + nameRegistry.fee();

        // Bid below the price and fail
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));

        // Bid above the price and succeed
        vm.prank(bob);
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testBidOnLastStep(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1 ether);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        // After 393 steps, we expect the bid premium to be 0.000000000000001000 after errors
        vm.warp(biddableTs + (8 hours * 393));
        uint256 bidPremium = 0.000000000000001 ether;
        uint256 bidPrice = bidPremium + nameRegistry.fee();

        // Bid below the price and fail
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));

        // Bid above the price and succeed
        vm.prank(bob);
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testBidAfterLastStep(address alice, address bob, address recovery) public {
        _assumeClean(bob);
        _assumeClean(alice);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1 ether);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        // After 393 steps, we expect the bid premium to be 0.0 after errors
        vm.warp(biddableTs + (8 hours * 394));
        uint256 bidPrice = nameRegistry.fee();

        // Bid slightly lower than the bidPrice which fails
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));

        // Bid with the bidPrice which succeeds
        vm.prank(bob);
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testBidShouldClearRecoveryClock(
        address alice,
        address bob,
        address charlie,
        address recovery1,
        address recovery2
    ) public {
        _assumeClean(alice);
        _assumeClean(charlie);
        _assumeClean(recovery1);
        vm.assume(alice != recovery1);
        vm.assume(bob != address(0));
        vm.assume(charlie != address(0));
        _register(alice);
        uint256 biddableTs = block.timestamp + REGISTRATION_PERIOD + RENEWAL_PERIOD;

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery1);

        // recovery1 requests a recovery of @alice to bob
        vm.prank(recovery1);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), block.timestamp);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery1);

        // charlie completes a bid on alice
        vm.warp(biddableTs);
        vm.deal(charlie, 1001 ether);
        vm.prank(charlie);
        nameRegistry.bid{value: 1001 ether}(charlie, ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.balanceOf(charlie), 1);
        assertEq(expiry(ALICE_TOKEN_ID), block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), charlie);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery2);
    }

    function testCannotBidWithUnderpayment(address alice, address bob, address recovery, uint256 amount) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        // Ensure that amount is always less than the bid + fee
        amount = (amount % (BID_START + FEE));
        vm.deal(bob, amount);

        vm.warp(biddableTs);
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: amount}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(bob.balance, amount);
    }

    function testCannotBidWhenRegistered(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        uint256 registerTs = block.timestamp;

        vm.prank(bob);
        // Register alice and fast-forward to one second before the name expires
        vm.warp(registerTs + REGISTRATION_PERIOD - 1);
        vm.expectRevert(NameRegistry.NotBiddable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), registerTs + REGISTRATION_PERIOD);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfRenewable(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        vm.warp(renewableTs);
        vm.prank(bob);
        vm.expectRevert(NameRegistry.NotBiddable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfInvitable(address bob, address recovery) public {
        _assumeClean(bob);

        // Fast forward to 2022 when registrations are possible
        vm.warp(JAN1_2023_TS);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfRegistrable(address bob, address recovery) public {
        _assumeClean(bob);

        // Fast forward to 2022 when registrations are possible and move to Registrable
        vm.warp(JAN1_2023_TS);
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfPaused(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1001 ether);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        vm.warp(biddableTs);

        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(bob);
        vm.expectRevert("Pausable: paused");
        nameRegistry.bid{value: (BID_START + FEE)}(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.balanceOf(alice), 1); // balanceOf counts expired ids by design
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(bob.balance, 1001 ether);
    }

    function testCannotBidFromNonPayableIfOverpaying(address alice, address charlie) public {
        _assumeClean(alice);
        _register(alice);
        address nonPayable = address(this);
        vm.deal(nonPayable, 1001 ether);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        vm.warp(biddableTs);
        vm.prank(nonPayable);
        vm.expectRevert(NameRegistry.CallFailed.selector);
        // call register() from address(this) which is non-payable
        // overpay by 1 wei to return funds which causes the revert
        nameRegistry.bid{value: (BID_START + FEE + 1 wei)}(nonPayable, ALICE_TOKEN_ID, charlie);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1); // balanceOf counts expired ids by design
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.balanceOf(nonPayable), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(nonPayable.balance, 1001 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-721 TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerOf(address alice) public {
        _assumeClean(alice);
        _register(alice);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
    }

    function testOwnerOfRevertsIfExpired(address alice) public {
        _assumeClean(alice);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        // Warp until the name is renewable
        vm.warp(renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.ownerOf(ALICE_TOKEN_ID);

        // Warp until the name is biddable
        vm.warp(biddableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.ownerOf(ALICE_TOKEN_ID);
    }

    function testOwnerOfRevertsIfInvitableOrRegistrable() public {
        vm.expectRevert("ERC721: invalid token ID");
        nameRegistry.ownerOf(ALICE_TOKEN_ID);
    }

    function testSafeTransferFromOwner(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _requestRecovery(alice, recovery);

        // alice transfers @alice to bob
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.safeTransferFrom(alice, bob, ALICE_TOKEN_ID);

        // assert that @alice is owned by bob and that the recovery request was reset
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testSafeTransferFromApprover(address alice, address bob, address approver, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _assumeClean(recovery);
        _assumeClean(approver);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        vm.assume(approver != alice);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _requestRecovery(alice, recovery);

        // alice sets charlie as her approver
        vm.prank(alice);
        nameRegistry.approve(approver, ALICE_TOKEN_ID);

        // alice transfers @alice to bob
        vm.prank(approver);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.safeTransferFrom(alice, bob, ALICE_TOKEN_ID);

        // assert that @alice is owned by bob and that the recovery request was reset
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotSafeTransferIfFnameExpired(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != bob);
        vm.assume(bob != address(0));
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        // Warp to renewable state and attempt a transfer
        vm.warp(renewableTs);
        vm.startPrank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.safeTransferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);

        // Warp to biddable state and attempt a transfer
        vm.warp(biddableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.safeTransferFrom(alice, bob, ALICE_TOKEN_ID);
        vm.stopPrank();

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotSafeTransferFromIfPaused(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        // Pause the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.safeTransferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotSafeTransferFromIfRegistrable(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        vm.warp(JAN1_2023_TS);

        vm.prank(alice);
        vm.expectRevert("ERC721: invalid token ID");
        nameRegistry.safeTransferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotSafeTransferFromIfNotOwner(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        vm.prank(bob);
        vm.expectRevert("ERC721: caller is not token owner nor approved");
        nameRegistry.safeTransferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotSafeTransferFromToZeroAddress(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        vm.prank(alice);
        vm.expectRevert("ERC721: transfer to the zero address");
        nameRegistry.safeTransferFrom(alice, address(0), ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testTransferFromOwner(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _requestRecovery(alice, recovery);

        // alice transfers @alice to bob
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        // assert that @alice is owned by bob and that the recovery request was reset
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testTransferFromApprover(address alice, address bob, address approver, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        _assumeClean(approver);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        vm.assume(approver != alice);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _requestRecovery(alice, recovery);

        // alice sets charlie as her approver
        vm.prank(alice);
        nameRegistry.approve(approver, ALICE_TOKEN_ID);

        // alice transfers @alice to bob
        vm.prank(approver);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        // assert that @alice is owned by bob and that the recovery request was reset
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTransferFromIfFnameExpired(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != bob);
        vm.assume(bob != address(0));
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        // Warp to renewable state and attempt a transfer
        vm.warp(renewableTs);
        vm.startPrank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);

        // Warp to biddable state and attempt a transfer
        vm.warp(biddableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);
        vm.stopPrank();

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTransferFromIfPaused(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        // Pause the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTransferFromIfRegistrable(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        vm.warp(JAN1_2023_TS);

        vm.prank(alice);
        vm.expectRevert("ERC721: invalid token ID");
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTransferFromIfNotOwner(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        vm.prank(bob);
        vm.expectRevert("ERC721: caller is not token owner nor approved");
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTransferFromToZeroAddress(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        vm.prank(alice);
        vm.expectRevert("ERC721: transfer to the zero address");
        nameRegistry.transferFrom(alice, address(0), ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
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

    function testChangeRecoveryAddress(address alice, address recovery1, address recovery2) public {
        _assumeClean(alice);
        vm.assume(alice != recovery1);
        vm.assume(recovery1 != address(0));
        _register(alice);

        // alice sets recovery1 as her recovery address and requests a recovery
        _requestRecovery(alice, recovery1);

        // alice sets recovery2 as her recovery address
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(ALICE_TOKEN_ID, recovery2);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(_recovery(ALICE_TOKEN_ID), recovery2);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCannotChangeRecoveryAddressUnlessOwner(
        address alice,
        address bob,
        address recovery1,
        address recovery2
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(recovery1 != address(0));
        vm.assume(recovery2 != address(0));
        _register(alice);

        // alice sets recovery1 as her recovery address and requests a recovery
        uint256 requestTs = _requestRecovery(alice, recovery1);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(_recovery(ALICE_TOKEN_ID), recovery1);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
    }

    function testCannotChangeRecoveryAddressIfExpired(address alice, address recovery1, address recovery2) public {
        _assumeClean(alice);
        _assumeClean(recovery1);
        vm.assume(recovery1 != address(0));
        vm.assume(recovery2 != address(0));
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        // alice sets recovery1 as her recovery address and requests a recovery
        uint256 requestTs = _requestRecovery(alice, recovery1);

        // Warp to when name is renewable
        vm.warp(renewableTs);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(_recovery(ALICE_TOKEN_ID), recovery1);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);

        // Warp to when name is biddable
        vm.warp(biddableTs);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(_recovery(ALICE_TOKEN_ID), recovery1);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
    }

    function testCannotChangeRecoveryAddressIfRegistrable(address alice, address recovery) public {
        _assumeClean(alice);
        vm.assume(alice != recovery);
        vm.assume(recovery != address(0));

        vm.prank(alice);
        vm.expectRevert("ERC721: invalid token ID");
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCannotChangeRecoveryAddressIfPaused(address alice, address recovery1, address recovery2) public {
        _assumeClean(alice);
        _assumeClean(recovery1);
        vm.assume(alice != recovery1);
        vm.assume(recovery1 != address(0));
        vm.assume(recovery2 != address(0));
        _register(alice);

        // alice sets recovery1 as her recovery address and requests a recovery
        uint256 requestTs = _requestRecovery(alice, recovery1);

        // the contract is paused
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // alice tries to change her recovery address again
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(_recovery(ALICE_TOKEN_ID), recovery1);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
    }

    /*//////////////////////////////////////////////////////////////
                         REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery(address alice, address bob, address charlie, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), address(0));

        // Request a recovery from alice to bob
        vm.prank(recovery);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), block.timestamp);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), bob);

        // Request another recovery from alice to charlie after some time has elapsed
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, charlie);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), block.timestamp);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), charlie);
    }

    function testCannotRequestRecoveryToZeroAddr(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        _register(alice);

        // Start a recovery to set recoveryClockOf and recoveryDestinationOf to non-zero values
        uint256 requestTs = _requestRecovery(alice, recovery);

        // recovery requests a recovery of alice's id to 0x0
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.InvalidRecovery.selector);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, address(0));

        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), recovery);
    }

    function testCannotRequestRecoveryUnlessRecoveryAddress(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(bob != recovery);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        // bob requests a recovery of @alice to bob, which fails
        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRequestRecoveryIfPaused(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        // Set and request a recovery so that recoveryClockOf is non-zero
        uint256 requestTs = _requestRecovery(alice, recovery);

        // pause the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // recovery requests a recovery which fails
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(recovery);
        vm.expectRevert("Pausable: paused");
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, recovery);

        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
    }

    /*//////////////////////////////////////////////////////////////
                         COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteRecovery(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        // set recovery as the recovery address and request a recovery of @alice from alice to bob
        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        // after escrow period, complete the recovery to bob
        vm.prank(recovery);
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        if (alice != bob) assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), bob);
    }

    function testRecoveryCompletionResetsERC721Approvals(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _requestRecovery(alice, recovery);

        // set recovery as the approver address for the ERC-721 token
        vm.prank(alice);
        nameRegistry.approve(recovery, ALICE_TOKEN_ID);

        // after escrow period, complete the recovery to bob
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.prank(recovery);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(recovery), 1);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), recovery);
        assertEq(_recovery(ALICE_TOKEN_ID), address(0));
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryUnlessRecovery(address alice, address recovery, address notRecovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(recovery != notRecovery);
        vm.assume(notRecovery != address(0));
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        // notRecovery tries and fails to complete the recovery
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.prank(notRecovery);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        if (alice != notRecovery) {
            assertEq(nameRegistry.balanceOf(notRecovery), 0);
        }
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryIfNotStarted(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        vm.warp(block.number + ESCROW_PERIOD);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), address(0));
    }

    function testCannotCompleteRecoveryWhenInEscrow(address alice, address recovery, uint256 waitPeriod) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);
        waitPeriod = waitPeriod % ESCROW_PERIOD;

        vm.warp(block.timestamp + waitPeriod);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.Escrow.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryIfExpired(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 biddableTs = renewableTs + RENEWAL_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        // Fast forward to renewal and attempt to recover
        vm.warp(renewableTs);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), recovery);

        // Fast forward to biddable and attempt to recover
        vm.warp(biddableTs);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryIfPaused(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        uint256 requestTs = _requestRecovery(alice, recovery);

        // ADMIN pauses the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // Fast forward to when the escrow period is completed
        vm.warp(requestTs + ESCROW_PERIOD);

        // 3. recovery attempts to complete the recovery, which fails
        vm.prank(recovery);
        vm.expectRevert("Pausable: paused");
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(expiry(ALICE_TOKEN_ID), renewableTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), requestTs);
        assertEq(recoveryDestination(ALICE_TOKEN_ID), recovery);
    }

    /*//////////////////////////////////////////////////////////////
                          CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        if (alice != bob) assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryFromRecoveryAddress(address alice, address bob, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        vm.prank(recovery);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(recovery, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        if (alice != bob) assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryIfPaused(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        _requestRecovery(alice, recovery);

        // pause the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryIfRenewable(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _requestRecovery(alice, recovery);

        vm.warp(renewableTs);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryIfBiddable(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 biddableTs = block.timestamp + REGISTRATION_PERIOD + RENEWAL_PERIOD;

        _requestRecovery(alice, recovery);

        vm.warp(biddableTs);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCannotCancelRecoveryIfNotStarted(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), 0);
    }

    function testCannotCancelRecoveryIfUnauthorized(address alice, address recovery, address bob) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        vm.assume(bob != recovery);
        vm.assume(bob != alice);
        _register(alice);

        _requestRecovery(alice, recovery);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery(ALICE_TOKEN_ID), recovery);
        assertEq(_recoveryTs(ALICE_TOKEN_ID), block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                           DEFAULT ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testGrantAdminRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);
    }

    function testRevokeAdminRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);

        vm.prank(defaultAdmin);
        nameRegistry.revokeRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);
    }

    function testCannotGrantAdminRoleUnlessDefaultAdmin(address alice, address bob) public {
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

    function testGrantDefaultAdminRole(address newDefaultAdmin) public {
        vm.assume(defaultAdmin != newDefaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), false);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);
    }

    function testCannotGrantDefaultAdminRoleUnlessDefaultAdmin(address newDefaultAdmin, address alice) public {
        _assumeClean(alice);
        vm.assume(alice != defaultAdmin);
        vm.assume(newDefaultAdmin != defaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), false);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), false);
    }

    function testRevokeDefaultAdminRole(address newDefaultAdmin) public {
        vm.prank(defaultAdmin);
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);

        vm.prank(newDefaultAdmin);
        nameRegistry.revokeRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), false);
        if (defaultAdmin != newDefaultAdmin) {
            assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);
        }
    }

    function testCannotRevokeDefaultAdminRoleUnlessDefaultAdmin(address newDefaultAdmin, address alice) public {
        _assumeClean(alice);
        vm.assume(defaultAdmin != newDefaultAdmin);
        vm.assume(alice != defaultAdmin && alice != newDefaultAdmin);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
        nameRegistry.revokeRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(nameRegistry.hasRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin), true);
    }

    /*//////////////////////////////////////////////////////////////
                             MODERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testReclaimRegisteredNames(
        address[4] calldata users,
        address mod,
        address[4] calldata recoveryAddresses,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](13);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
            addresses[i + 8] = recoveryAddresses[i];
        }
        addresses[12] = mod;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewalTs = block.timestamp + REGISTRATION_PERIOD;
        _grant(MODERATOR_ROLE, mod);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recoveryAddresses[i]);
        }

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }

        vm.prank(mod);
        nameRegistry.reclaim(reclaimActions);

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(nameRegistry.balanceOf(users[i]), 0);
            assertEq(nameRegistry.balanceOf(destinations[i]), 1);
            assertEq(expiry(tokenIds[i]), renewalTs);
            assertEq(nameRegistry.ownerOf(tokenIds[i]), destinations[i]);
            assertEq(_recovery(tokenIds[i]), address(0));
            assertEq(_recoveryTs(tokenIds[i]), 0);
        }
    }

    function testReclaimRegisteredNamesCloseToExpiryShouldExtend(
        address[4] calldata users,
        address mod,
        address recovery,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        addresses[8] = mod;
        addresses[9] = recovery;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewalTs = block.timestamp + REGISTRATION_PERIOD;
        _grant(MODERATOR_ROLE, mod);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recovery);
        }

        // Fast forward to just before the renewals expire
        vm.warp(renewalTs - 1);
        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }
        vm.prank(mod);
        nameRegistry.reclaim(reclaimActions);

        // reclaim should extend the expiry ahead of the current timestamp
        uint256 expectedExpiryTs = block.timestamp + RENEWAL_PERIOD;

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(nameRegistry.balanceOf(users[i]), 0);
            assertEq(nameRegistry.balanceOf(destinations[i]), 1);
            assertEq(expiry(tokenIds[i]), expectedExpiryTs);
            assertEq(nameRegistry.ownerOf(tokenIds[i]), destinations[i]);
            assertEq(_recovery(tokenIds[i]), address(0));
            assertEq(_recoveryTs(tokenIds[i]), 0);
        }
    }

    function testReclaimExpiredNames(
        address[4] calldata users,
        address mod,
        address recovery,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        addresses[8] = mod;
        addresses[9] = recovery;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        _grant(MODERATOR_ROLE, mod);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recovery);
        }

        vm.warp(renewableTs);
        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }
        vm.prank(mod);
        nameRegistry.reclaim(reclaimActions);

        // reclaim should extend the expiry ahead of the current timestamp
        uint256 expectedExpiryTs = block.timestamp + RENEWAL_PERIOD;

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(nameRegistry.balanceOf(users[i]), 0);
            assertEq(nameRegistry.balanceOf(destinations[i]), 1);
            assertEq(expiry(tokenIds[i]), expectedExpiryTs);
            assertEq(nameRegistry.ownerOf(tokenIds[i]), destinations[i]);
            assertEq(_recovery(tokenIds[i]), address(0));
            assertEq(_recoveryTs(tokenIds[i]), 0);
        }
    }

    function testReclaimBiddableNames(
        address[4] calldata users,
        address mod,
        address recovery,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        addresses[8] = mod;
        addresses[9] = recovery;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 biddableTs = block.timestamp + REGISTRATION_PERIOD + RENEWAL_PERIOD;
        _grant(MODERATOR_ROLE, ADMIN);

        for (uint256 i = 0; i < fnames.length; i++) {
            _requestRecovery(users[i], tokenIds[i], recovery);
        }

        vm.warp(biddableTs);
        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
            vm.expectEmit(true, true, true, true);
            emit Transfer(users[i], destinations[i], tokenIds[i]);
        }
        vm.prank(ADMIN);
        nameRegistry.reclaim(reclaimActions);

        // reclaim should extend the expiry ahead of the current timestamp
        uint256 expectedExpiryTs = block.timestamp + RENEWAL_PERIOD;

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(nameRegistry.balanceOf(users[i]), 0);
            assertEq(nameRegistry.balanceOf(destinations[i]), 1);
            assertEq(expiry(tokenIds[i]), expectedExpiryTs);
            assertEq(nameRegistry.ownerOf(tokenIds[i]), destinations[i]);
            assertEq(_recovery(tokenIds[i]), address(0));
            assertEq(_recoveryTs(tokenIds[i]), 0);
        }
    }

    function testReclaimResetsERC721Approvals(
        address[4] calldata users,
        address[4] calldata approveUsers,
        address[4] calldata destinations
    ) public {
        address[] memory addresses = new address[](12);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = approveUsers[i];
            addresses[i + 8] = destinations[i];
        }
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        _grant(MODERATOR_ROLE, ADMIN);

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            nameRegistry.approve(approveUsers[i], tokenIds[i]);
        }

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }
        vm.prank(ADMIN);
        nameRegistry.reclaim(reclaimActions);

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(nameRegistry.getApproved(tokenIds[i]), address(0));
        }
    }

    function testReclaimWhenPaused(address[4] calldata users, address[4] calldata destinations) public {
        address[] memory addresses = new address[](8);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
        }
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }
        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;

        _grant(MODERATOR_ROLE, ADMIN);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(ADMIN);
        nameRegistry.pause();

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < users.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }
        vm.prank(ADMIN);
        vm.expectRevert("Pausable: paused");
        nameRegistry.reclaim(reclaimActions);

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(expiry(tokenIds[i]), renewableTs);
            assertEq(nameRegistry.ownerOf(tokenIds[i]), users[i]);
        }
    }

    function testCannotReclaimIfRegistrable(address mod, address[4] calldata destinations) public {
        address[] memory addresses = new address[](5);
        for (uint256 i = 0; i < destinations.length; i++) {
            addresses[i] = destinations[i];
        }
        addresses[4] = mod;
        _assumeUniqueAndClean(addresses);
        _grant(MODERATOR_ROLE, mod);

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }

        vm.prank(mod);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.reclaim(reclaimActions);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(nameRegistry.balanceOf(destinations[i]), 0);
            assertEq(expiry(tokenIds[i]), 0);
            vm.expectRevert("ERC721: invalid token ID");
            assertEq(nameRegistry.ownerOf(tokenIds[i]), address(0));
            assertEq(_recovery(tokenIds[i]), address(0));
            assertEq(_recoveryTs(tokenIds[i]), 0);
        }
    }

    function testCannotReclaimUnlessModerator(
        address[4] calldata users,
        address[4] calldata destinations,
        address notModerator,
        address[4] calldata recoveryAddresses
    ) public {
        address[] memory addresses = new address[](13);
        for (uint256 i = 0; i < users.length; i++) {
            addresses[i] = users[i];
            addresses[i + 4] = destinations[i];
            addresses[i + 8] = recoveryAddresses[i];
        }
        addresses[12] = notModerator;
        _assumeUniqueAndClean(addresses);

        for (uint256 i = 0; i < fnames.length; i++) {
            _register(users[i], fnames[i]);
        }

        uint256 renewableTs = block.timestamp + REGISTRATION_PERIOD;
        uint256 recoveryTs;
        for (uint256 i = 0; i < fnames.length; i++) {
            recoveryTs = _requestRecovery(users[i], tokenIds[i], recoveryAddresses[i]);
        }

        NameRegistry.ReclaimAction[] memory reclaimActions = new NameRegistry.ReclaimAction[](4);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            reclaimActions[i] = NameRegistry.ReclaimAction(tokenIds[i], destinations[i]);
        }

        vm.prank(notModerator);
        vm.expectRevert(NameRegistry.NotModerator.selector);
        nameRegistry.reclaim(reclaimActions);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(nameRegistry.balanceOf(users[i]), 1);
            assertEq(nameRegistry.balanceOf(destinations[i]), 0);
            assertEq(expiry(tokenIds[i]), renewableTs);
            assertEq(nameRegistry.ownerOf(tokenIds[i]), users[i]);
            assertEq(_recovery(tokenIds[i]), recoveryAddresses[i]);
            assertEq(_recoveryTs(tokenIds[i]), recoveryTs);
        }
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeTrustedCaller(address alice) public {
        vm.assume(alice != nameRegistry.trustedCaller());

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedCaller(alice);
        nameRegistry.changeTrustedCaller(alice);

        assertEq(nameRegistry.trustedCaller(), alice);
    }

    function testCannotChangeTrustedCallerUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        address trustedCaller = nameRegistry.trustedCaller();
        vm.assume(bob != trustedCaller);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changeTrustedCaller(bob);

        assertEq(nameRegistry.trustedCaller(), trustedCaller);
    }

    function testDisableTrustedCaller() public {
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();
        assertEq(nameRegistry.trustedOnly(), 0);
    }

    function testCannotDisableTrustedCallerUnlessAdmin(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.disableTrustedOnly();

        assertEq(nameRegistry.trustedOnly(), 1);
    }

    function testChangeVault(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.vault(), VAULT);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ChangeVault(bob);
        nameRegistry.changeVault(bob);

        assertEq(nameRegistry.vault(), bob);
    }

    function testCannotChangeVaultUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.vault(), VAULT);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changeVault(bob);

        assertEq(nameRegistry.vault(), VAULT);
    }

    function testChangePool(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.pool(), POOL);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ChangePool(bob);
        nameRegistry.changePool(bob);

        assertEq(nameRegistry.pool(), bob);
    }

    function testCannotChangePoolUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.pool(), POOL);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changePool(bob);

        assertEq(nameRegistry.pool(), POOL);
    }

    /*//////////////////////////////////////////////////////////////
                             TREASURER TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeFee(address alice, uint256 fee) public {
        vm.assume(alice != FORWARDER);
        _grant(TREASURER_ROLE, alice);
        assertEq(nameRegistry.fee(), 0.01 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ChangeFee(fee);
        nameRegistry.changeFee(fee);

        assertEq(nameRegistry.fee(), fee);
    }

    function testCannotChangeFeeUnlessTreasurer(address alice, uint256 fee) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.changeFee(fee);
    }

    function testWithdrawFunds(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(alice);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether - amount);
        assertEq(VAULT.balance, amount);
    }

    function testCannotWithdrawUnlessTreasurer(address alice, uint256 amount) public {
        _assumeClean(alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether);
        assertEq(VAULT.balance, 0);
    }

    function testCannotWithdrawInvalidAmount(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        amount = amount % AMOUNT_FUZZ_MAX;
        vm.deal(address(nameRegistry), amount);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.withdraw(amount + 1 wei);

        assertEq(address(nameRegistry).balance, amount);
        assertEq(VAULT.balance, 0);
    }

    function testCannotWithdrawToNonPayableAddress(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(ADMIN);
        nameRegistry.changeVault(address(this));

        vm.prank(alice);
        vm.expectRevert(NameRegistry.CallFailed.selector);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether);
        assertEq(VAULT.balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             OPERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    // Tests that cover pausing and its implications on other functions live alongside unit tests
    // for the functions

    function testCannotPauseUnlessOperator(address alice) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.pause();
    }

    function testCannotUnpauseUnlessOperator(address alice) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Register the username @alice to the address on Jan 1, 2023
    function _register(address alice) internal {
        _register(alice, "alice");
    }

    /// @dev Register the username to the user address on Jan 1, 2023
    function _register(address user, bytes16 username) internal {
        _disableTrusted();

        vm.deal(user, 10_000 ether);
        vm.warp(JAN1_2023_TS);

        vm.startPrank(user);
        bytes32 commitHash = nameRegistry.generateCommit(username, user, "secret", address(0));
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);

        nameRegistry.register{value: nameRegistry.fee()}(username, user, "secret", address(0));
        vm.stopPrank();
    }

    /// @dev vm.assume that the address does not match known contracts
    function _assumeClean(address a) internal {
        for (uint256 i = 0; i < knownContracts.length; i++) {
            vm.assume(a != knownContracts[i]);
        }

        vm.assume(a > MAX_PRECOMPILE);
        vm.assume(a != ADMIN);
    }

    /// @dev vm.assume that the address are unique
    function _assumeUniqueAndClean(address[] memory addresses) internal {
        for (uint256 i = 0; i < addresses.length - 1; i++) {
            for (uint256 j = i + 1; j < addresses.length; j++) {
                vm.assume(addresses[i] != addresses[j]);
            }
            _assumeClean(addresses[i]);
        }
        _assumeClean(addresses[addresses.length - 1]);
    }

    /// @dev Helper that assigns the recovery address and then requests a recovery
    function _requestRecovery(address alice, address recovery) internal returns (uint256 requestTs) {
        return _requestRecovery(alice, ALICE_TOKEN_ID, recovery);
    }

    /// @dev Helper that assigns the recovery address and then requests a recovery
    function _requestRecovery(address user, uint256 tokenId, address recovery) internal returns (uint256 requestTs) {
        vm.prank(user);
        nameRegistry.changeRecoveryAddress(tokenId, recovery);
        assertEq(_recovery(tokenId), recovery);
        assertEq(_recoveryTs(tokenId), 0);

        vm.prank(recovery);
        nameRegistry.requestRecovery(tokenId, recovery);
        assertEq(_recoveryTs(tokenId), block.timestamp);
        assertEq(_recovery(tokenId), recovery);
        return block.timestamp;
    }

    function _disableTrusted() internal {
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();
    }

    function _grant(bytes32 role, address target) internal {
        vm.prank(defaultAdmin);
        nameRegistry.grantRole(role, target);
    }
}
