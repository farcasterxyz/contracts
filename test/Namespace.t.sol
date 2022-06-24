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
                        CONSTANTS
    //////////////////////////////////////////////////////////////*/
    address alice = address(0x123);
    address bob = address(0x456);
    address admin = address(0x001);

    uint256 aliceTokenId = uint256(bytes32("alice"));
    uint256 aliceRegisterTs = 1655933973; // Wed, Jun 22, 2022 21:39:33 GMT
    uint256 aliceRenewTs = 1672531200; // Sun, Jan 1, 2023 0:00:00 GMT
    uint256 aliceRenewYear = 2023;
    uint256 aliceAuctionTs = 1675123200; // Tue, Jan 31, 2023 0:00:00 GMT

    function setUp() public {
        namespace = new Namespace("Farcaster Namespace", "FCN", admin);
    }

    /*//////////////////////////////////////////////////////////////
                            Timing Tests
    //////////////////////////////////////////////////////////////*/

    function testCurrentYear() public {
        // Date between Oct 1 2022 and Oct 1 2023, should return Oct 1 2023.
        vm.warp(1640095200);
        assertEq(namespace.currentYear(), 2021);

        // Date before between Oct 1 2021 and Oct 1 2022
        vm.warp(aliceRegisterTs);
        assertEq(namespace.currentYear(), 2022);
    }

    function testFailCurrentYearBefore2021() public {
        // Thursday, December 10, 2020 0:00:00
        vm.warp(1607558400);
        namespace.currentYear();
    }

    function testCurrentYearAfter2122ReturnsZero() public {
        // Thursday, December 10, 2122 0:00:00
        vm.warp(4826304000);
        assertEq(namespace.currentYear(), 0);
    }

    // Add test for the last year and the firts years.

    function testCurrentYearPayment() public {
        vm.warp(aliceRegisterTs);
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
        // 1. Give alice money and fast forward to 2022 to begin registration.
        fundAlice();
        vm.startPrank(alice);

        // 2. Generate and make the commit
        bytes32 commitHash = namespace.generateCommit("alice", alice, "secret");
        namespace.makeCommit(commitHash);

        // 3. Register the name andy.
        uint256 balance = alice.balance;

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), alice, uint256(bytes32("alice")));

        namespace.register{value: 0.01 ether}("alice", alice, "secret");
        vm.stopPrank();

        // 4. Check that excess funds were returned
        assertEq(alice.balance, balance - namespace.currentYearPayment());
    }

    function testCannotRegisterWithoutPayment() public {
        vm.warp(aliceRegisterTs);
        bytes32 commitHash = namespace.generateCommit("alice", alice, "secret");
        namespace.makeCommit(commitHash);

        vm.expectRevert(InsufficientFunds.selector);
        namespace.register{value: 0.001 ether}("alice", alice, "secret");
    }

    function testCannotRegisterWithInvalidCommit(address owner, bytes32 secret) public {
        // Set up the commit
        vm.warp(aliceRegisterTs);

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
        vm.startPrank(alice);
        registerAlice(alice);

        // Fast-forward to the next year (2023) when the registration expires
        vm.warp(aliceRenewTs);

        // Renew alice's subscription
        vm.expectEmit(true, true, true, true);
        emit Renew(aliceTokenId, alice, aliceRenewYear + 1);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        // TODO: assert that funds are charged correctly

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), 2024);
        vm.stopPrank();
    }

    function testCannotRenewEarly() public {
        vm.startPrank(alice);
        registerAlice(alice);

        // Fast forward to the last second of this year (2022) when the registration is still valid
        vm.warp(aliceRenewTs - 1);

        // Try to renew the subscription
        vm.expectRevert(NotRenewable.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), aliceRenewYear);
        vm.stopPrank();
    }

    function testCannotRenewUnlessOwner() public {
        vm.startPrank(alice);
        registerAlice(alice);

        // Fast-forward to the next year (2023) when the registration expires
        vm.warp(aliceRenewTs);

        // Try to renew it from another address
        vm.expectRevert(Unauthorized.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, address(this));

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), aliceRenewYear);
        vm.stopPrank();
    }

    function testCannotRenewWithoutPayment() public {
        vm.startPrank(alice);
        registerAlice(alice);

        // Fast-forward to the next year (2023) when the registration expires
        vm.warp(aliceRenewTs);

        // Try to register without sending money
        vm.expectRevert(InsufficientFunds.selector);
        namespace.renew(aliceTokenId, alice);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), aliceRenewYear);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testAuctionBidImmediately() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        // Fast-forward to start of auction
        vm.warp(aliceAuctionTs);
        vm.deal(bob, 200_000 ether);
        vm.startPrank(bob);

        // Bid should fail when under max price
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 99_999.999999 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), alice);

        // Bid should succeed at max price
        namespace.bid{value: 100_000 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), bob);
        vm.stopPrank();

        // Bid should fail if triggered again (sanity check)
        vm.prank(alice);
        vm.expectRevert(NotForAuction.selector);
        namespace.bid(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), bob);
    }

    function testAuctionBidAfterOneStep() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        // Fast-forward to the second step
        vm.warp(aliceAuctionTs + 25 hours);
        vm.deal(bob, 200_000 ether);
        vm.startPrank(bob);

        // Bid should fail under target price (0.5^1 * 100_000 == 50_000)
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 49_999.999999 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), alice);

        // Bid should succeed over target price
        namespace.bid{value: 50_000 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), bob);
        vm.stopPrank();
    }

    function testAuctionBidOnLastStep() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        // Fast-forward to the last step
        vm.warp(aliceAuctionTs + 25 days - 1 hours);
        vm.deal(bob, 200_000 ether);
        vm.startPrank(bob);

        // Bid should fail under target price (0.5^23 * 100_000 == 0.011920929)
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 0.01191 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), alice);

        // Bid should succeed over target price
        namespace.bid{value: 0.01193 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), bob);
        vm.stopPrank();
    }

    function testAuctionBidFlatRate() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        vm.warp(aliceAuctionTs + 25 days);
        vm.deal(bob, 200_000 ether);
        vm.startPrank(bob);

        // Expect it to revert with insufficient fees
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 0.009 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), alice);

        // Bid should complete at fee rate
        namespace.bid{value: namespace.fee()}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), bob);
        vm.stopPrank();
    }

    function testCannotAuctionIfNotExpired() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        // Fast forward to the second before the auction starts
        vm.warp(aliceAuctionTs - 1);

        // Bid should fail
        vm.expectRevert(NotForAuction.selector);
        namespace.bid(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), alice);
    }

    /*//////////////////////////////////////////////////////////////
                            RECLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function testReclaim() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        // Reclaim the name from the admin account
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, namespace.vault(), aliceTokenId);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);

        // Sanity check ownership and expiration
        assertEq(namespace.ownerOf(aliceTokenId), namespace.vault());
        assertEq(namespace.expiryYearOf(aliceTokenId), aliceRenewYear);
    }

    function testReclaimShouldRenewExpiredNames() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        // Let the name expire and then reclaim the name from the admin account
        vm.warp(aliceAuctionTs);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, namespace.vault(), aliceTokenId);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);

        // Sanity check ownership and expiration dates
        assertEq(namespace.ownerOf(aliceTokenId), namespace.vault());
        assertEq(namespace.expiryYearOf(aliceTokenId), namespace.currentYear() + 1);
    }

    function testCannotReclaimUnlessMinted() public {
        vm.expectRevert(NotMinted.selector);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function registerAlice(address who) internal {
        fundAlice();

        bytes32 commitHash = namespace.generateCommit("alice", who, "secret");
        namespace.makeCommit(commitHash);

        namespace.register{value: namespace.fee()}("alice", who, "secret");
        assertEq(namespace.expiryYearOf(aliceTokenId), 2023);
    }

    // Set up alice's account with funds and fast forward to 2022
    function fundAlice() internal {
        vm.deal(alice, 100_000 ether);
        vm.warp(aliceRegisterTs);
    }
}

// TODO: Registering twice breaks?
