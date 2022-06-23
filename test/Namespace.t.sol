// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/Namespace.sol";

contract NameSpaceTest is Test {
    Namespace namespace;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Renew(uint256 indexed tokenId, address indexed to, uint256 expiry);

    event Reclaim(uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        namespace = new Namespace("Farcaster Namespace", "FCN");
    }

    address alice = address(0x123);
    // GMT Wednesday, June 22, 2022 21:39:33
    uint256 aliceRegistrationTimestamp = 1655933973;
    uint256 aliceExpiryYear = 2023;

    /*//////////////////////////////////////////////////////////////
                            Timing Tests
    //////////////////////////////////////////////////////////////*/

    function testCurrentYear() public {
        // Date between Oct 1 2022 and Oct 1 2023, should return Oct 1 2023.
        vm.warp(1640095200);
        assertEq(namespace.currentYear(), 2021);

        // Date before between Oct 1 2021 and Oct 1 2022
        vm.warp(aliceRegistrationTimestamp);
        assertEq(namespace.currentYear(), 2022);
    }

    function testFailCurrentYearBefore2021() public {
        // Thursday, December 10, 2020 0:00:00
        vm.warp(1607558400);
        assertEq(namespace.currentYear(), 2021);
    }

    function testFailCurrentYearAfter2122() public {
        // Thursday, December 10, 2122 0:00:00
        vm.warp(4826304000);
        assertEq(namespace.currentYear(), 2022);
    }

    // Add test for the last year and the firts years.

    function testCurrentYearPayment() public {
        vm.warp(aliceRegistrationTimestamp);
        assertEq(namespace.currentYearPayment(), 0.005262946156773211 ether);
    }

    /*//////////////////////////////////////////////////////////////
                               COMMIT TESTS
    //////////////////////////////////////////////////////////////*/

    // TODO: Verify that the hash values are what we expect
    function testGenerateCommit() public {
        // alphabetic name
        bytes32 commit1 = namespace.generateCommit("alice", alice, "secret");
        assertEq(commit1, 0xe89b588f69839d6c3411027709e47c05713159feefc87e3173f64c01f4b41c72);

        // 1-char name
        bytes32 commit2 = namespace.generateCommit("1", alice, "secret");
        assertEq(commit2, 0xf52e7be4097c2afdc86002c691c7e5fab52be36748174fe15303bb32cb106da6);

        // 16-char alphabetic
        bytes32 commit3 = namespace.generateCommit("alicenwonderland", alice, "secret");
        assertEq(commit3, 0x94f5dd34daadfe7565398163e7cb955832b2a2e963a6365346ab8ba92b5f5126);

        // 16-char alphanumeric name
        bytes32 commit4 = namespace.generateCommit("alice0wonderland", alice, "secret");
        assertEq(commit4, 0xdf1dc48666da9fcc229a254aa77ffab008da2d29b617fada59b645b7cc0928b9);

        // 16-char alphanumeric hyphenated name
        bytes32 commit5 = namespace.generateCommit("-al1c3w0nderl4nd", alice, "secret");
        assertEq(commit5, 0x48ba82e0c3aa3f6a18bff166ca475b8cb257b83768160ee7e2702e9834d7380d);
    }

    function testCannotCommitWithInvalidName() public {
        vm.expectRevert(InvalidName.selector);
        namespace.generateCommit("Alice", alice, "secret");

        vm.expectRevert(InvalidName.selector);
        namespace.generateCommit("a/lice", alice, "secret");

        vm.expectRevert(InvalidName.selector);
        namespace.generateCommit("a:lice", alice, "secret");

        vm.expectRevert(InvalidName.selector);
        namespace.generateCommit("a`ice", alice, "secret");

        vm.expectRevert(InvalidName.selector);
        namespace.generateCommit("a{ice", alice, "secret");

        // We cannot specify valid UTF-8 chars like £ in a test using string literals, so we encode
        // a bytes16 string that has the second character set to a byte-value of 129, which is a
        // valid UTF-8 character that cannot be typed
        bytes16 nameWithInvalidUtfChar = 0x61816963650000000000000000000000;
        vm.expectRevert(InvalidName.selector);
        namespace.generateCommit(nameWithInvalidUtfChar, alice, "secret");
    }

    /*//////////////////////////////////////////////////////////////
                            REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister() public {
        vm.warp(aliceRegistrationTimestamp);
        bytes32 commitHash = namespace.generateCommit("alice", alice, "secret");
        namespace.makeCommit(commitHash);

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), address(this), uint256(bytes32("alice")));
        namespace.register{value: 0.01 ether}("alice", alice, "secret");
    }

    function testCannotRegisterWithoutPayment() public {
        vm.warp(aliceRegistrationTimestamp);
        bytes32 commitHash = namespace.generateCommit("alice", alice, "secret");
        namespace.makeCommit(commitHash);

        vm.expectRevert(InsufficientFunds.selector);
        namespace.register{value: 0.001 ether}("alice", alice, "secret");
    }

    function testCannotRegisterWithInvalidCommit(address owner, bytes32 secret) public {
        // Set up the commit
        vm.warp(aliceRegistrationTimestamp);

        bytes16 username = "bob";
        bytes32 commitHash = namespace.generateCommit(username, owner, secret);
        namespace.makeCommit(commitHash);

        // Register using a different owner address
        address incorrectOwner = address(0x1234A);
        vm.assume(owner != incorrectOwner);
        vm.expectRevert(InvalidCommit.selector);
        namespace.register{value: 0.01 ether}(username, incorrectOwner, secret);

        // Register using an incorrect secret
        bytes32 incorrectSecret = "foobar";
        vm.assume(secret != incorrectSecret);
        vm.expectRevert(InvalidCommit.selector);
        namespace.register{value: 0.01 ether}(username, owner, incorrectSecret);

        // Register using an incorrect name
        bytes16 incorrectUsername = "alice";
        vm.expectRevert(InvalidCommit.selector);
        namespace.register{value: 0.01 ether}(incorrectUsername, owner, secret);
    }

    function testCannotRegisterWithInvalidNames(address owner, bytes32 secret) public {
        bytes16 incorrectUsername = "al{ce";
        bytes32 invalidCommit = keccak256(abi.encode(incorrectUsername, owner, secret));
        namespace.makeCommit(invalidCommit);

        // Register using an incorrect name
        vm.expectRevert(InvalidName.selector);
        namespace.register{value: 0.01 ether}(incorrectUsername, owner, secret);
    }

    /*//////////////////////////////////////////////////////////////
                            RENEW TESTS
    //////////////////////////////////////////////////////////////*/

    function testRenew() public {
        registerAlice();
        uint256 aliceExpiryTimestamp = namespace.timestampOfYear(aliceExpiryYear);
        assertEq(namespace.expiryYearOf(tokenIdAlice()), 2023);

        // let the registration expire and renew it
        vm.warp(aliceExpiryTimestamp);
        vm.expectEmit(true, true, true, true);
        emit Renew(tokenIdAlice(), address(this), aliceExpiryYear + 1);
        namespace.renew{value: 0.01 ether}(tokenIdAlice(), address(this));

        // sanity check ownership and expiration
        assertEq(namespace.ownerOf(tokenIdAlice()), address(this));
        assertEq(namespace.expiryYearOf(tokenIdAlice()), 2024);
    }

    function testCannotRenewEarly() public {
        registerAlice();
        uint256 aliceExpiryTimestamp = namespace.timestampOfYear(aliceExpiryYear);

        // fast forward until just before the expiration
        vm.warp(aliceExpiryTimestamp - 1);

        // assert the failure
        vm.expectRevert(NotRenewable.selector);
        namespace.renew{value: 0.01 ether}(tokenIdAlice(), address(this));

        // sanity check ownership and expiration
        assertEq(namespace.ownerOf(tokenIdAlice()), address(this));
        assertEq(namespace.expiryYearOf(tokenIdAlice()), aliceExpiryYear);
    }

    function testCannotRenewUnlessOwner() public {
        registerAlice();

        // let the registration expire and renew it
        vm.warp(namespace.timestampOfYear(aliceExpiryYear));
        vm.expectRevert(Unauthorized.selector);
        namespace.renew{value: 0.01 ether}(tokenIdAlice(), alice);

        // sanity check ownership and expiration
        assertEq(namespace.ownerOf(tokenIdAlice()), address(this));
        assertEq(namespace.expiryYearOf(tokenIdAlice()), aliceExpiryYear);
    }

    function testCannotRenewWithoutPayment() public {
        registerAlice();
        uint256 nextYear = namespace.currentYear() + 1;

        // let the registration expire and renew it
        vm.warp(namespace.timestampOfYear(nextYear));
        vm.expectRevert(InsufficientFunds.selector);
        namespace.renew(tokenIdAlice(), address(this));

        // sanity check ownership and expiration
        assertEq(namespace.ownerOf(tokenIdAlice()), address(this));
        assertEq(namespace.expiryYearOf(tokenIdAlice()), nextYear);
    }

    /*//////////////////////////////////////////////////////////////
                            RECLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function testReclaim() public {
        registerAlice();
        uint256 aliceExpiry = namespace.timestampOfYear(aliceExpiryYear);
        uint256 aliceReclaimable = aliceExpiry + namespace.gracePeriod();

        // let it expire and reach the renewal period
        vm.warp(aliceReclaimable);

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(this), namespace.vault(), tokenIdAlice());
        namespace.reclaim(tokenIdAlice());

        // sanity check ownership and expiration
        assertEq(namespace.ownerOf(tokenIdAlice()), namespace.vault());
        assertEq(namespace.expiryYearOf(tokenIdAlice()), aliceExpiryYear);
    }

    function testCannotReclaimBeforeGracePeriodExpires() public {
        registerAlice();
        uint256 aliceExpiry = namespace.timestampOfYear(aliceExpiryYear);
        uint256 aliceReclaimable = aliceExpiry + namespace.gracePeriod();

        // warp to just before the reclaim period
        vm.warp(aliceReclaimable - 1);
        vm.expectRevert(NotReclaimable.selector);
        namespace.reclaim(tokenIdAlice());

        // sanity check ownership and expiration
        assertEq(namespace.ownerOf(tokenIdAlice()), address(this));
        assertEq(namespace.expiryYearOf(tokenIdAlice()), aliceExpiryYear);
    }

    function testCannotReclaimUnlessMinted() public {
        vm.expectRevert(NotMinted.selector);
        namespace.reclaim(tokenIdAlice());
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    // Warp to a time in 2022 and register alice
    function registerAlice() internal {
        vm.warp(aliceRegistrationTimestamp);
        bytes32 commitHash = namespace.generateCommit("alice", alice, "secret");
        namespace.makeCommit(commitHash);
        namespace.register{value: 0.01 ether}("alice", alice, "secret");
    }

    function tokenIdAlice() internal pure returns (uint256) {
        return uint256(bytes32("alice"));
    }
}
