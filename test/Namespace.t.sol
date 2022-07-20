// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "../src/Namespace.sol";

contract NameSpaceTest is Test {
    Namespace namespace;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Renew(uint256 indexed tokenId, address indexed to, uint256 expiry);

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

    uint256 timestamp2023 = 1672531200; // Sun, Jan 1, 2023 0:00:00 GMT
    uint256 timestamp2024 = 1704067200; // Sun, Jan 1, 2024 0:00:00 GMT

    uint256 aliceTokenId = uint256(bytes32("alice"));
    uint256 aliceRegisterTs = 1655933973; // Wed, Jun 22, 2022 21:39:33 GMT
    uint256 aliceRenewableTs = timestamp2023; // Sun, Jan 1, 2023 0:00:00 GMT
    uint256 aliceBiddableTs = 1675123200; // Tue, Jan 31, 2023 0:00:00 GMT

    function setUp() public {
        namespace = new Namespace("Farcaster Namespace", "FCN", admin, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        GENERATE COMMIT TESTS
    //////////////////////////////////////////////////////////////*/

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
        vm.deal(alice, 10_000 ether);
        vm.warp(aliceRegisterTs);

        // 2. Make the commitment to register the name alice, but deliver it to bob
        vm.startPrank(alice);
        bytes32 commitHash = namespace.generateCommit("alice", bob, "secret");
        namespace.makeCommit(commitHash);

        // 3. Register the name alice, and deliver it to bob
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), bob, uint256(bytes32("alice")));
        uint256 balance = alice.balance;
        namespace.register{value: 0.01 ether}("alice", bob, "secret");

        // 4. Assert that the name was registered and the balance was returned.
        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(alice.balance, balance - namespace.currYearFee());
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);

        // 5. Check that comitting and minting again fails
        namespace.makeCommit(commitHash);
        vm.expectRevert(NotRegistrable.selector);
        namespace.register{value: 0.01 ether}("alice", bob, "secret");

        // 6. Check that alice can still mint another name to bob
        bytes32 commitHashMorty = namespace.generateCommit("morty", bob, "secret");
        namespace.makeCommit(commitHashMorty);
        namespace.register{value: 0.01 ether}("morty", bob, "secret");
        assertEq(namespace.ownerOf(uint256(bytes32("morty"))), bob);
        assertEq(namespace.balanceOf(bob), 2);

        vm.stopPrank();
    }

    function testCannotRegisterWithoutPayment() public {
        vm.deal(alice, 10_000 ether);
        vm.warp(aliceRegisterTs);

        vm.startPrank(alice);
        bytes32 commitHash = namespace.generateCommit("alice", alice, "secret");
        namespace.makeCommit(commitHash);

        vm.expectRevert(InsufficientFunds.selector);
        namespace.register{value: 1 wei}("alice", alice, "secret");
        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidCommit(address owner, bytes32 secret) public {
        // 1. Fund alice and set up the commit hashes to register the name bob
        vm.deal(alice, 10_000 ether);
        vm.warp(aliceRegisterTs);

        bytes16 username = "bob";
        bytes32 commitHash = namespace.generateCommit(username, owner, secret);

        // 2. Attempt to register the name before making the commit
        vm.startPrank(alice);
        vm.expectRevert(InvalidCommit.selector);
        namespace.register{value: 0.01 ether}(username, owner, secret);

        namespace.makeCommit(commitHash);

        // 3. Attempt to register using an incorrect owner address
        address incorrectOwner = address(0x1234A);
        vm.assume(owner != incorrectOwner);
        vm.expectRevert(InvalidCommit.selector);
        namespace.register{value: 0.01 ether}(username, incorrectOwner, secret);

        // 4. Attempt to register using an incorrect secret
        bytes32 incorrectSecret = "foobar";
        vm.assume(secret != incorrectSecret);
        vm.expectRevert(InvalidCommit.selector);
        namespace.register{value: 0.01 ether}(username, owner, incorrectSecret);

        // 5. Attempt to register using an incorrect name
        bytes16 incorrectUsername = "alice";
        vm.expectRevert(InvalidCommit.selector);
        namespace.register{value: 0.01 ether}(incorrectUsername, owner, secret);
        vm.stopPrank();
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
        // 1. Register alice and fast forward to renewal
        registerAlice();
        vm.warp(aliceRenewableTs);

        // 2. Alice renews her own username
        vm.expectEmit(true, true, true, true);
        emit Renew(aliceTokenId, alice, timestamp2024);
        vm.prank(alice);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testRenewOther() public {
        // 1. Register alice and fast forward to renewal
        registerAlice();
        vm.warp(aliceRenewableTs);

        // 2. Bob renews alice's username for her
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Renew(aliceTokenId, alice, timestamp2024);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testRenewWithOverpayment() public {
        registerAlice();
        vm.warp(aliceRenewableTs);

        // Renew alice's registration, but overpay the amount
        vm.startPrank(alice);
        uint256 balance = alice.balance;
        namespace.renew{value: 0.02 ether}(aliceTokenId, alice);
        vm.stopPrank();

        assertEq(alice.balance, balance - 0.01 ether);
        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testCannotRenewWithoutPayment() public {
        // 1. Register alice and fast-forward to renewal
        registerAlice();
        vm.warp(aliceRenewableTs);

        // 2. Renewing fails if insufficient funds are provided
        vm.prank(alice);
        vm.expectRevert(InsufficientFunds.selector);
        namespace.renew(aliceTokenId, alice);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
    }

    function testCannotRenewIfRegistrable() public {
        // 1. Fund alice and fast-forward to 2022, when registrations can occur
        vm.deal(alice, 10_000 ether);
        vm.warp(aliceRegisterTs);

        // 2. Renewing fails if insufficient funds are provided
        vm.prank(alice);
        vm.expectRevert(Registrable.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        vm.expectRevert(Registrable.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.expiryOf(aliceTokenId), 0);
    }

    function testCannotRenewIfOwnerIncorrect() public {
        // 1. Register alice and fast-forward to 2023, when the registration is in renewal.
        registerAlice();
        vm.warp(aliceRenewableTs);

        // 2. Renewing fails if the owner is specified incorrectly
        vm.prank(alice);
        vm.expectRevert(IncorrectOwner.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, bob);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
    }

    function testCannotRenewIfBiddable() public {
        // 1. Register alice and fast-forward to 2023 when the registration expires
        registerAlice();
        vm.warp(aliceBiddableTs);

        vm.prank(alice);
        vm.expectRevert(Biddable.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
    }

    function testCannotRenewIfRegistered() public {
        // Fast forward to the last second of this year (2022) when the registration is still valid
        registerAlice();
        vm.warp(aliceRenewableTs - 1);

        vm.prank(alice);
        vm.expectRevert(Registered.selector);
        namespace.renew{value: 0.01 ether}(aliceTokenId, alice);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
    }

    /*//////////////////////////////////////////////////////////////
                            BID TESTS
    //////////////////////////////////////////////////////////////*/

    function testBidImmediately() public {
        // 1. Register alice and fast-forward to the start of the auction
        registerAlice();
        vm.prank(alice);
        namespace.approve(bob, aliceTokenId);
        vm.warp(aliceBiddableTs);

        // 2. Bob bids and fails because bid < premium + fee
        vm.deal(bob, 1001 ether);
        vm.startPrank(bob);
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 1000 ether}(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);
        assertEq(namespace.getApproved(aliceTokenId), bob);

        // 3. Bob bids and succeeds because bid >= premium + fee
        namespace.bid{value: 1_000.01 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
        assertEq(namespace.getApproved(aliceTokenId), address(0));

        // 4. Alice bids again and fails because the name is no longer for auction
        vm.prank(alice);
        vm.expectRevert(NotBiddable.selector);
        namespace.bid(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testBidAndOverpay() public {
        // 1. Register alice and fast-forward to the start of the auction
        registerAlice();
        vm.warp(aliceBiddableTs);

        // 2. Bob bids and overpays
        vm.deal(bob, 1001 ether);
        vm.prank(bob);
        namespace.bid{value: 1001 ether}(aliceTokenId);

        // 3. Check that bob's change is returned to him correctly
        assertEq(bob.balance, 0.990821917808219179 ether);
    }

    function testBidAfterOneStep() public {
        // 1. Register alice and fast-forward to 8 hours into the auction
        registerAlice();
        vm.warp(aliceBiddableTs + 8 hours);

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
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);

        // 3. Bob bids and succeeds because bid > price
        namespace.bid{value: 898 ether}(aliceTokenId);
        assertEq(namespace.ownerOf(aliceTokenId), bob);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testBidOnHundredthStep() public {
        // 1. Register alice and fast-forward to 800 hours into the auction
        registerAlice();
        vm.warp(aliceBiddableTs + (8 hours * 100));

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
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);

        // 3. Bob bids and succeeds because bid > price
        namespace.bid{value: 0.0279218 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testBidOnPenultimateStep() public {
        // 1. Register alice and fast-forward to 3056 hours into the auction
        registerAlice();
        vm.warp(aliceBiddableTs + (8 hours * 382));

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
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);

        // 3. Bob bids and succeeds because bid > price
        namespace.bid{value: 0.005689498772 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testBidFlatRate() public {
        registerAlice();
        vm.warp(aliceBiddableTs + (8 hours * 383));
        vm.deal(bob, 1000 ether);
        vm.startPrank(bob);

        // 2. Bob bids and fails because bid < price (0 + fee) == 0.0056803653
        vm.expectRevert(InsufficientFunds.selector);
        namespace.bid{value: 0.0056803652 ether}(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(bob), 0);
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);

        // 3. Bob bids and succeeds because bid > price (0 + fee)
        namespace.bid{value: 0.0056803653 ether}(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), bob);
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 1);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testCannotBidUnlessBiddable() public {
        // 1. Register alice and fast-forward to one second before the auction starts
        registerAlice();

        // 2. Bid during registered state should fail
        vm.startPrank(bob);
        vm.warp(aliceRenewableTs - 1);
        vm.expectRevert(NotBiddable.selector);
        namespace.bid(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);

        // 2. Bid during renewable state should fail
        vm.warp(aliceBiddableTs - 1);
        vm.expectRevert(NotBiddable.selector);
        namespace.bid(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
        vm.stopPrank();
    }

    function testBidShouldClearRecovery() public {
        // 1. Register alice and set up a recovery address.
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. Bob requests a recovery of @alice to Charlie
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);

        // 3. Bob completes a bid on alice
        vm.warp(aliceBiddableTs);
        vm.deal(bob, 1001 ether);
        namespace.bid{value: 1001 ether}(aliceTokenId);
        vm.stopPrank();

        // 4. Assert that the recovery state has been unset
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testCannotBidIfRegistrable() public {
        // 1. Bid on @alice when it is not minted
        vm.prank(bob);
        vm.expectRevert(Registrable.selector);
        namespace.bid(aliceTokenId);

        vm.expectRevert(Registrable.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 0);
        assertEq(namespace.balanceOf(bob), 0);
        assertEq(namespace.expiryOf(aliceTokenId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-721 TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerOfRevertsIfExpired() public {
        registerAlice();

        vm.warp(aliceBiddableTs);
        vm.expectRevert(Expired.selector);
        namespace.ownerOf(aliceTokenId);
    }

    function testOwnerOfRevertsIfRegistrable() public {
        vm.expectRevert(Registrable.selector);
        namespace.ownerOf(aliceTokenId);
    }

    function testTransferFromResetsRecovery() public {
        // 1. Register alice and set up a recovery address.
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

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

    function testTransferFromCannotTransferExpiredName() public {
        // 1. Register alice and set up a recovery address.
        registerAlice();

        // 2. Fast forward to name in renewable state
        vm.startPrank(alice);
        vm.warp(aliceRenewableTs);
        vm.expectRevert(Expired.selector);
        namespace.transferFrom(alice, bob, aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.balanceOf(alice), 1);
        assertEq(namespace.balanceOf(bob), 0);

        // 3. Fast forward to name in expired state
        vm.warp(aliceBiddableTs);
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
        registerAlice();

        // 1. alice sets bob as her recovery address
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit SetRecoveryAddress(bob, aliceTokenId);

        namespace.setRecoveryAddress(aliceTokenId, bob);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);

        // 2. alice sets charlie as her recovery address
        vm.expectEmit(true, true, false, true);
        emit SetRecoveryAddress(charlie, aliceTokenId);
        namespace.setRecoveryAddress(aliceTokenId, charlie);
        assertEq(namespace.recoveryOf(aliceTokenId), charlie);

        vm.stopPrank();
    }

    function testCannotSetRecoveryUnlessOwner() public {
        registerAlice();

        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        namespace.setRecoveryAddress(aliceTokenId, charlie);

        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testCannotSetRecoveryIfExpired() public {
        registerAlice();

        vm.warp(aliceRenewableTs);
        vm.startPrank(alice);
        vm.expectRevert(Expired.selector);
        namespace.setRecoveryAddress(aliceTokenId, charlie);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));

        vm.warp(aliceBiddableTs);
        vm.expectRevert(Expired.selector);
        namespace.setRecoveryAddress(aliceTokenId, charlie);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));

        vm.stopPrank();
    }

    function testCannotSetRecoveryIfRegistrable() public {
        uint256 bobTokenId = uint256(bytes32("bob"));

        vm.expectRevert(Registrable.selector);
        vm.prank(alice);
        namespace.setRecoveryAddress(bobTokenId, bob);

        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testCannotSetSelfAsRecovery() public {
        registerAlice();

        vm.prank(alice);
        vm.expectRevert(InvalidRecovery.selector);
        namespace.setRecoveryAddress(aliceTokenId, alice);

        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery() public {
        // 1. alice registers id 1 and sets bob as her recovery address
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. bob requests a recovery of alice's id to charlie
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(aliceTokenId, alice, charlie);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), charlie);

        // 3. bob then requests another recovery to david
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, david);

        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), david);
    }

    function testCannotRequestRecoveryToZeroAddr() public {
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 1. bob requests a recovery of alice's id to 0x0
        vm.prank(bob);
        vm.expectRevert(InvalidRecovery.selector);
        namespace.requestRecovery(aliceTokenId, alice, address(0));

        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), address(0));
    }

    function testCannotRequestRecoveryUnlessAuthorized() public {
        registerAlice();

        // 1. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), address(0));
    }

    function testCannotRequestRecoveryIfRegistrable() public {
        // 1. bob requests a recovery from alice to charlie, which fails
        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.recoveryDestinationOf(aliceTokenId), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRecoveryCompletion() public {
        // 1. alice registers @alice and sets bob as her recovery address and approver
        registerAlice();
        vm.startPrank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);
        namespace.approve(bob, aliceTokenId);
        vm.stopPrank();

        // 2. bob requests a recovery of alice's id to charlie
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. after escrow period, bob completes the recovery to charlie
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, aliceTokenId);
        namespace.completeRecovery(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), charlie);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
        assertEq(namespace.getApproved(aliceTokenId), address(0));
    }

    function testCannotCompleteRecoveryIfUnauthorized() public {
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 1. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 2. alice unsets bob as her recovery, bob calls completeRecovery on @alice, which fails
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, address(0));

        vm.prank(bob);
        vm.expectRevert(Unauthorized.selector);
        namespace.completeRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
    }

    function testCannotCompleteRecoveryIfNotStarted() public {
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 1. bob calls recovery complete on alice's id, which fails
        vm.prank(bob);
        vm.warp(block.number + escrowPeriod);
        vm.expectRevert(NoRecovery.selector);
        namespace.completeRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
    }

    function testCannotCompleteRecoveryWhenInEscrow() public {
        // 1. alice registers @alice and sets bob as her recovery address
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. before escrow period, bob completes the recovery to charlie
        vm.expectRevert(Escrow.selector);
        namespace.completeRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
        vm.stopPrank();
    }

    function testCannotCompleteRecoveryIfExpired() public {
        // 1. alice registers @alice and sets bob as her recovery address
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. bob requests a recovery of @alice to charlie
        uint256 requestTs = block.timestamp;
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. during the renewal period, bob attempts to recover to charlie
        vm.warp(aliceRenewableTs);
        vm.expectRevert(Unauthorized.selector);
        namespace.completeRecovery(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), requestTs);

        // 3. during expiry, bob attempts to recover to charlie
        vm.warp(aliceBiddableTs);
        vm.expectRevert(Unauthorized.selector);
        namespace.completeRecovery(aliceTokenId);

        vm.expectRevert(Expired.selector);
        assertEq(namespace.ownerOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryOf(aliceTokenId), bob);
        assertEq(namespace.recoveryClockOf(aliceTokenId), requestTs);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress() public {
        // 1. alice registers @alice and sets bob as her recovery address
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. alice cancels the recovery
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit CancelRecovery(aliceTokenId);
        namespace.cancelRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectRevert(NoRecovery.selector);
        vm.prank(bob);
        namespace.completeRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
    }

    function testCancelRecoveryFromRecoveryAddress() public {
        // 1. alice registers @alice and sets bob as her recovery address
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.startPrank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. bob cancels the recovery
        vm.expectEmit(true, false, false, false);
        emit CancelRecovery(aliceTokenId);
        namespace.cancelRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);

        // 4. after escrow period, bob tries to recover to charlie and fails
        vm.warp(block.timestamp + escrowPeriod);
        vm.expectRevert(NoRecovery.selector);
        namespace.completeRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        vm.stopPrank();
    }

    function testCannotCancelRecoveryIfNotStarted() public {
        // 1. alice registers @alice and sets bob as her recovery address
        registerAlice();
        vm.startPrank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. alice cancels the recovery which fails
        vm.expectRevert(NoRecovery.selector);
        namespace.cancelRecovery(aliceTokenId);
        vm.stopPrank();

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
    }

    function testCannotCancelRecoveryIfUnauthorized() public {
        // 1. alice registers @alice and sets bob as her recovery address
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        // 2. bob requests a recovery of @alice to charlie
        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        // 3. charlie cancels the recovery which fails
        vm.prank(charlie);
        vm.expectRevert(Unauthorized.selector);
        namespace.cancelRecovery(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), alice);
        assertEq(namespace.recoveryClockOf(aliceTokenId), block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testReclaimRegisteredNames() public {
        registerAlice();
        vm.prank(alice);
        namespace.approve(bob, aliceTokenId);

        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, namespace.vault(), aliceTokenId);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), namespace.vault());
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
        assertEq(namespace.getApproved(aliceTokenId), address(0));
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
    }

    function testReclaimRenewableNames() public {
        registerAlice();

        vm.warp(aliceRenewableTs);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, namespace.vault(), aliceTokenId);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), namespace.vault());
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testReclaimBiddableNames() public {
        registerAlice();

        vm.warp(aliceBiddableTs);
        vm.expectEmit(true, true, true, false);
        emit Transfer(alice, namespace.vault(), aliceTokenId);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), namespace.vault());
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2024);
    }

    function testCannotReclaimUnlessMinted() public {
        vm.expectRevert(Registrable.selector);
        vm.prank(admin);
        namespace.reclaim(aliceTokenId);
    }

    function testReclaimResetsRecoveryState() public {
        registerAlice();
        vm.prank(alice);
        namespace.setRecoveryAddress(aliceTokenId, bob);

        vm.prank(bob);
        namespace.requestRecovery(aliceTokenId, alice, charlie);

        vm.prank(admin);
        namespace.reclaim(aliceTokenId);

        assertEq(namespace.ownerOf(aliceTokenId), namespace.vault());
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
        assertEq(namespace.recoveryOf(aliceTokenId), address(0));
        assertEq(namespace.recoveryClockOf(aliceTokenId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        YEARLY PAYMENTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCurrYear() public {
        // Incorrectly returns 2021 for any date before 2021
        vm.warp(1607558400); // GMT Thursday, December 10, 2020 0:00:00
        assertEq(namespace.currYear(), 2021);

        // Works correctly for known year range [2021 - 2037]
        vm.warp(1640095200); // GMT Tuesday, December 21, 2021 14:00:00
        assertEq(namespace.currYear(), 2021);

        vm.warp(1670889599); // GMT Monday, December 12, 2022 23:59:59
        assertEq(namespace.currYear(), 2022);

        // Does not work after 2037
        vm.warp(2161114288); // GMT Friday, January 1, 2038 0:00:00
        vm.expectRevert(InvalidTime.selector);
        assertEq(namespace.currYear(), 0);
    }

    function testCurrYearPayment() public {
        vm.warp(1672531200); // GMT Friday, January 1, 2023 0:00:00
        assertEq(namespace.currYearFee(), 0.01 ether);

        vm.warp(1688256000); // GMT Sunday, July 2, 2023 0:00:00
        assertEq(namespace.currYearFee(), 0.005013698630136986 ether);

        vm.warp(1704023999); // GMT Friday, Dec 31, 2023 11:59:59
        assertEq(namespace.currYearFee(), 0.000013698947234906 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function registerAlice() internal {
        vm.deal(alice, 10_000 ether);
        vm.warp(aliceRegisterTs);

        vm.startPrank(alice);
        bytes32 commitHash = namespace.generateCommit("alice", alice, "secret");
        namespace.makeCommit(commitHash);

        namespace.register{value: namespace.fee()}("alice", alice, "secret");
        assertEq(namespace.expiryOf(aliceTokenId), timestamp2023);
        vm.stopPrank();
    }
}
