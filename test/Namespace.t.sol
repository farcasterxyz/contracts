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

    event SetRecoveryAddress(address indexed recovery, uint256 indexed tokenId);

    event RequestRecovery(uint256 indexed id, address indexed from, address indexed to);

    event CancelRecovery(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS
    //////////////////////////////////////////////////////////////*/
    address admin = address(0x001);
    address alice = address(0x123);
    address bob = address(0x456);
    address charlie = address(0x789);
    address david = address(0x531);

    uint256 escrowPeriod = 3 days;

    uint256 aliceTokenId = uint256(bytes32("alice"));
    uint256 aliceRegisterTs = 1655933973; // Wed, Jun 22, 2022 21:39:33 GMT
    uint256 aliceRenewTs = 1672531200; // Sun, Jan 1, 2023 0:00:00 GMT
    uint256 aliceRenewYear = 2023;
    uint256 aliceExpiredTs = 1675123200; // Tue, Jan 31, 2023 0:00:00 GMT

    function setUp() public {
        namespace = new Namespace("Farcaster Namespace", "FCN", admin, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        YEARLY PAYMENTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCurrentYear() public {
        // Works correctly for current year
        vm.warp(1640095200); // GMT Tuesday, December 21, 2021 14:00:00
        assertEq(namespace.currYear(), 2021);

        // Does not work before 2021
        vm.warp(1607558400); // GMT Thursday, December 10, 2020 0:00:00
        assertEq(namespace.currYear(), 2021);

        // Does not work after 2037
        vm.warp(2161114288); // GMT Friday, January 1, 2038 0:00:00
        vm.expectRevert(InvalidTime.selector);
        assertEq(namespace.currYear(), 0);
    }

    function testCurrentYearPayment() public {
        vm.warp(1672531200); // GMT Friday, January 1, 2023 0:00:00
        assertEq(namespace.currYearFee(), 0.01 ether);

        vm.warp(1688256000); // GMT Sunday, July 2, 2023 0:00:00
        assertEq(namespace.currYearFee(), 0.005013698630136986 ether);

        vm.warp(1704023999); // GMT Friday, Dec 31, 2023 11:59:59
        assertEq(namespace.currYearFee(), 0.000013698947234906 ether);
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
        vm.startPrank(alice);
        fundAlice();

        // 2. Make the commitment to register the name alice, but deliver it to bob
        bytes32 commitHash = namespace.generateCommit("alice", bob, "secret");
        namespace.makeCommit(commitHash);

        // 3. Register the name alice, and deliver it to bob
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), bob, uint256(bytes32("alice")));

        uint256 balance = alice.balance;
        namespace.register{value: 0.01 ether}("alice", bob, "secret");
        vm.stopPrank();

        // 4. Assert that the name was registered and the balance was returned.
        assertEq(alice.balance, balance - namespace.currYearFee());
        assertEq(namespace.ownerOf(aliceTokenId), bob);
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

    function testRenewSelf() public {
        vm.startPrank(alice);
        registerAlice(alice);

        vm.warp(aliceRenewTs);

        // Alice renews her own registration
        vm.expectEmit(true, true, true, true);
        emit Renew(aliceTokenId, alice, aliceRenewYear + 1);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), 2024);
    }

    function testRenewOther() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        vm.warp(aliceRenewTs);

        // Bob renews alice's registration for her
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Renew(aliceTokenId, alice, aliceRenewYear + 1);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), 2024);
    }

    function testRenewWithOverpayment() public {
        vm.startPrank(alice);
        registerAlice(alice);

        vm.warp(aliceRenewTs);

        // Renew alice's registration, but overpay the amount
        uint256 balance = alice.balance;
        namespace.renew{value: 0.02 ether}(aliceTokenId, alice);
        vm.stopPrank();

        assertEq(alice.balance, balance - 0.01 ether);
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), 2024);
    }

    function testCannotRenewDuringAuction() public {
        vm.startPrank(alice);
        registerAlice(alice);

        // Renew alice's subscription during the auction and expect it to fail
        vm.warp(aliceExpiredTs);
        vm.expectRevert(Expired.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);
        vm.stopPrank();

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.expiryYearOf(aliceTokenId), 2023);
    }

    function testCannotRenewEarly() public {
        vm.startPrank(alice);
        registerAlice(alice);

        // Fast forward to the last second of this year (2022) when the registration is still valid
        vm.warp(aliceRenewTs - 1);

        // Try to renew the subscription
        vm.expectRevert(Registered.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryYearOf(aliceTokenId), aliceRenewYear);
        vm.stopPrank();
    }

    function testCannotRenewIfOwnerIncorrect() public {
        // 1. Register alice and fast-forward to 2023, when the registration expires.
        vm.startPrank(alice);
        registerAlice(alice);
        vm.warp(aliceRenewTs);

        // 2. Renewing fails if the owner is specified incorrectly
        vm.expectRevert(IncorrectOwner.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, bob);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.expiryYearOf(aliceTokenId), aliceRenewYear);
        vm.stopPrank();
    }

    function testCannotRenewWithoutPayment() public {
        // 1. Register alice and fast-forward to 2023, when the registration expires.
        vm.startPrank(alice);
        registerAlice(alice);
        vm.warp(aliceRenewTs);

        // 2. Renewing fails if insufficient funds are provided
        vm.expectRevert(InsufficientFunds.selector);
        namespace.renew(aliceTokenId, alice);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.expiryYearOf(aliceTokenId), aliceRenewYear);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testAuctionBidImmediately() public {
        // 1. Register alice and fast-forward to the start of the auction
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();
        vm.warp(aliceExpiredTs);

        // 2. Bob bids and fails because bid < premium + fee
        vm.deal(bob, 1001 ether);
        vm.startPrank(bob);
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 1000 ether}(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);

        // 3. Bob bids and succeeds because bid >= premium + fee
        namespace.bid{value: 1_000.01 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);

        // 4. Alice bids again and fails because the name is no longer for auction
        vm.prank(alice);
        vm.expectRevert(NotExpired.selector);
        namespace.bid(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
    }

    function testAuctionBidAfterOneStep() public {
        // 1. Register alice and fast-forward to 8 hours into the auction
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();
        vm.warp(aliceExpiredTs + 8 hours);

        // 2. Bob bids and fails because bid < price (premium + fee)
        // price = (0.9^1 * 1_000) + 0.00916894977 = 900.009
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 897.303 ether}(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);

        // 3. Bob bids and succeeds because bid > price
        namespace.bid{value: 898 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), bob);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
    }

    function testAuctionBidOnHundredthStep() public {
        // 1. Register alice and fast-forward to 800 hours into the auction
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();
        vm.warp(aliceExpiredTs + (8 hours * 100));

        // 2. Bob bids and fails because bid < price (premium + fee)
        // price = (0.9^100 * 1_000) + 0.00826484018 = 0.0348262391
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 0.0279217 ether}(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);

        // 3. Bob bids and succeeds because bid > price
        namespace.bid{value: 0.0279218 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
    }

    function testAuctionBidOnPenultimateStep() public {
        // 1. Register alice and fast-forward to 3056 hours into the auction
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();
        vm.warp(aliceExpiredTs + (8 hours * 382));

        // 2. Bob bids and fails because bid < price (premium + fee)
        // price = (0.9^382 * 1_000) + 0.00568949772 = 0.00568949772 (+ ~ - 3.31e-15)
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 0.00568949771 ether}(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);

        // 3. Bob bids and succeeds because bid > price
        namespace.bid{value: 0.005689498772 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
    }

    function testAuctionBidFlatRate() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        vm.warp(aliceExpiredTs + (8 hours * 383));
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);

        // 2. Bob bids and fails because bid < price (0 + fee) == 0.0056803653
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 0.0056803652 ether}(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(bob), 0);
        assertEq(namespace.balanceOf(alice), 1);

        // 3. Bob bids and succeeds because bid > price (0 + fee)
        namespace.bid{value: 0.0056803653 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
    }

    function testCannotAuctionIfNotExpired() public {
        // 1. Register alice and fast-forward to one second before the auction starts
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();
        vm.warp(aliceExpiredTs - 1);

        // 2. Any bid should fail with the NotExpired error
        vm.expectRevert(NotExpired.selector);
        namespace.bid(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);
    }

    function testAuctionBidShouldClearRecovery() public {
        // 1. Register alice and set up a recovery address.
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        vm.startPrank(bob);

        // 2. Bob requests a recovery of @alice to Charlie
        namespace.requestRecovery(aliceTokenId, alice, charlie);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);

        // 3. Bob completes a bid on alice
        vm.warp(aliceExpiredTs);
        vm.deal(bob, 1001 ether);
        namespace.bid{value: 1001 ether}(aliceTokenId);
        vm.stopPrank();

        // 4. Assert that the recovery state has been unset
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransferFromResetsRecovery() public {
        // 1. Register alice and set up a recovery address.
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. Bob requests a recovery of @alice to Charlie
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);

        // 3. Alice transfers then name to david
        vm.prank(alice);
        namespace.transferFrom(alice, david, aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), david);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testTransferFromCannotTransferRenweableOrExpiredName() public {
        // 1. Register alice and set up a recovery address.
        vm.startPrank(alice);
        registerAlice(alice);

        // 2. Fast forward to name in renewable state
        vm.warp(aliceRenewTs);
        vm.expectRevert(Expired.selector);
        namespace.transferFrom(alice, bob, aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);

        // 3. Fast forward to name in expired state
        vm.warp(aliceExpiredTs);
        vm.expectRevert(Expired.selector);
        namespace.transferFrom(alice, bob, aliceTokenId);
        vm.stopPrank();

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SET RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetRecoveryAddress() public {
        vm.startPrank(alice);
        registerAlice(alice);

        // 2. alice sets bob as her recovery address
        vm.expectEmit(true, true, false, false);
        emit SetRecoveryAddress(bob, aliceTokenId);

        namespace.setRecoveryAddress(aliceTokenId, bob);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);

        // 3. alice sets charlie as her recovery address
        vm.expectEmit(true, true, false, false);
        emit SetRecoveryAddress(charlie, aliceTokenId);

        namespace.setRecoveryAddress(aliceTokenId, charlie);
        assertEq(namespace.recoveryOf(aliceTokenId), charlie);

        vm.stopPrank();
    }

    function testCannotSetRecoveryUnlessOwner() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        namespace.setRecoveryAddress(aliceTokenId, charlie);

        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testCannotSetRecoveryIfRenewable() public {
        vm.startPrank(alice);
        registerAlice(alice);
        vm.warp(aliceRenewTs);

        vm.expectRevert((Expired).selector);
        namespace.setRecoveryAddress(aliceTokenId, charlie);
        vm.stopPrank();

        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testCannotSetRecoveryForUnmintedToken() public {
        uint256 bobTokenId = uint256(bytes32("bob"));

        vm.expectRevert(NotRegistered.selector);
        vm.prank(alice);
        namespace.setRecoveryAddress(bobTokenId, bob);

        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testCannotSetSelfAsRecovery() public {
        vm.startPrank(alice);
        registerAlice(alice);

        // 2. alice sets herself as the recovery address, which fails
        vm.expectRevert(InvalidRecovery.selector);
        namespace.setRecoveryAddress(aliceTokenId, alice);
        vm.stopPrank();

        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(aliceTokenId, alice, charlie);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // sanity check ownership and recovery state
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), charlie);
    }

    function testRequestRecoverySequential() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie, and then requests one to david

        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(aliceTokenId, alice, david);
        namespace.requestRecovery(aliceTokenId, alice, david);

        // sanity check ownership and recovery state
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), david);
    }

    function testCannotRequestRecoveryUnlessAuthorized() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        vm.stopPrank();

        // 2. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // sanity check the ownership post transfer.
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), address(0));
    }

    function testCannotRequestRecoveryToZeroAddr() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to 0x0
        vm.prank(bob);
        vm.expectRevert(InvalidRecovery.selector);
        namespace.requestRecovery(aliceTokenId, alice, address(0));

        // sanity check ownership and recovery state
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRecoveryCompletion() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. after escrow period, bob completes the recovery to charlie
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, charlie, aliceTokenId);
        namespace.completeRecovery(aliceTokenId);
        vm.stopPrank();

        // sanity check the ownership and recovery state post completion
        assertEq(namespace.ownerOf(aliceTokenId), charlie);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
    }

    function testCannotCompleteRecoveryIfUnauthorized() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of @alice to charlie
        uint256 requestTs = block.timestamp;
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. charlie calls completeRecovery on @alice, which fails
        vm.prank(charlie);
        vm.warp(requestTs + escrowPeriod);
        vm.expectRevert(Unauthorized.selector);
        namespace.completeRecovery(aliceTokenId);

        // sanity check the ownership post transfer.
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), requestTs);
    }

    function testCannotCompleteRecoveryIfNotStarted() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob calls recovery complete on alice's id, which fails
        vm.prank(bob);
        vm.warp(block.number + escrowPeriod);
        vm.expectRevert(NoRecovery.selector);
        namespace.completeRecovery(aliceTokenId);

        // sanity check the ownership and recovery state post completion.
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
    }

    function testCannotCompleteRecoveryWhenInEscrow() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of @alice to charlie
        uint256 requestTs = block.timestamp;
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. before escrow period, bob completes the recovery to charlie
        vm.expectRevert(InEscrow.selector);
        namespace.completeRecovery(aliceTokenId);
        vm.stopPrank();

        // sanity check the ownership and recovery state post completion.
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), requestTs);
    }

    function testCannotCompleteRecoveryWhenInRenewal() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of @alice to charlie
        uint256 requestTs = block.timestamp;
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. during the renewal period, bob attempts to recover to charlie
        vm.warp(aliceRenewTs);
        vm.expectRevert(Unauthorized.selector);
        namespace.completeRecovery(aliceTokenId);
        vm.stopPrank();

        // sanity check the ownership and recovery state post completion.
        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), requestTs);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. alice cancels the recovery
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit CancelRecovery(aliceTokenId);
        namespace.cancelRecovery(aliceTokenId);

        // sanity check the ownership post cancellation
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectRevert(NoRecovery.selector);
        vm.prank(bob);
        namespace.completeRecovery(aliceTokenId);

        // sanity check the ownership and recovery state post cancellation
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
    }

    function testCancelRecoveryFromRecoveryAddress() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. bob cancels the recovery
        vm.prank(bob);
        vm.expectEmit(true, false, false, false);
        emit CancelRecovery(aliceTokenId);
        namespace.cancelRecovery(aliceTokenId);

        // sanity check the ownership post cancellation
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectRevert(NoRecovery.selector);
        vm.prank(bob);
        namespace.completeRecovery(aliceTokenId);

        // sanity check the ownership and recovery state post cancellation
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
    }

    function testCannotCancelRecoveryIfNotStarted() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. alice cancels the recovery which fails
        vm.expectRevert(NoRecovery.selector);
        namespace.cancelRecovery(aliceTokenId);
        vm.stopPrank();

        // sanity check the ownership and recovery state after cancellation
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
    }

    function testCannotCancelRecoveryIfUnauthorized() public {
        // 1. alice registers @alice and sets bob as her recovery address
        vm.startPrank(alice);
        registerAlice(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        vm.stopPrank();

        // 2. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. charlie cancels the recovery which fails
        vm.prank(charlie);
        vm.expectRevert(Unauthorized.selector);
        namespace.cancelRecovery(aliceTokenId);

        // sanity check the ownership and recovery state after cancellation
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
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
        vm.warp(aliceExpiredTs);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, namespace.vault(), aliceTokenId);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);

        // Sanity check ownership and expiration dates
        assertEq(namespace.ownerOf(aliceTokenId), namespace.vault());
        assertEq(namespace.expiryYearOf(aliceTokenId), namespace.currYear() + 1);
    }

    function testCannotReclaimUnlessMinted() public {
        vm.expectRevert(NotRegistered.selector);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);
    }

    /*//////////////////////////////////////////////////////////////
                           TEST HELPERS
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
