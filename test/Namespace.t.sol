// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/Namespace.sol";

contract NameSpaceTest is Test {
    Namespace namespace;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    // event Register(uint256 indexed id, address indexed to);

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        namespace = new Namespace();
    }

    address alice = address(0x123);

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

    function testRegister(address owner, bytes32 secret) public {
        bytes32 commitHash = namespace.generateCommit("alice", owner, secret);
        namespace.makeCommit(commitHash);
        // TODO: Expect Mint Event after ERC-721
        namespace.register("alice", owner, secret);
    }

    function testCannotRegisterWithInvalidInputs(address owner, bytes32 secret) public {
        // Set up the commit
        bytes16 username = "bob";
        bytes32 commitHash = namespace.generateCommit(username, owner, secret);
        namespace.makeCommit(commitHash);

        // Register using a different owner address
        address incorrectOwner = address(0x1234A);
        vm.assume(owner != incorrectOwner);
        vm.expectRevert(InvalidCommit.selector);
        namespace.register(username, incorrectOwner, secret);

        // Register using an incorrect secret
        bytes32 incorrectSecret = "foobar";
        vm.assume(secret != incorrectSecret);
        vm.expectRevert(InvalidCommit.selector);
        namespace.register(username, owner, incorrectSecret);

        // Register using an incorrect name
        bytes16 incorrectUsername = "alice";
        vm.expectRevert(InvalidCommit.selector);
        namespace.register(incorrectUsername, owner, secret);
    }
}
