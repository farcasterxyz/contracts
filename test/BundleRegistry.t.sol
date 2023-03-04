// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";

import "./TestConstants.sol";
import "./NameRegistryConstants.sol";

import {BundleRegistry} from "../src/BundleRegistry.sol";
import {BundleRegistryHarness} from "./Utils.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {IdRegistryHarness} from "./Utils.sol";
import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */

contract BundleRegistryTest is Test {
    /// Instance of the NameRegistry implementation
    NameRegistry nameRegistryImpl;

    // Instance of the NameRegistry proxy contract
    ERC1967Proxy nameRegistryProxy;

    // Instance of the NameRegistry proxy contract cast as the implementation contract
    NameRegistry nameRegistry;

    // Instance of the IdRegistry contract wrapped in its test wrapper
    IdRegistryHarness idRegistry;

    // Instance of the BundleRegistry contract wrapped in its test wrapper
    BundleRegistryHarness bundleRegistry;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ChangeTrustedCaller(address indexed trustedCaller, address indexed owner);

    event Register(address indexed to, uint256 indexed id, address recovery);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Address of known contracts
    address[] knownContracts = [
        address(0xCe71065D4017F316EC606Fe4422e11eB2c47c246), // FuzzerDict
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C), // CREATE2 Factory
        address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), // address(this)
        address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A), // FORWARDER
        address(0x185a4dc360CE69bDCceE33b3784B0282f7961aea), // ???
        address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D) // ???
    ];

    // Address of the test contract
    address owner = address(this);

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

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret,
        uint256 amount,
        uint256 commitDelay,
        uint256 registerDelay
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        vm.assume(amount >= nameRegistry.fee()); // the amount must be at least equal to the fee
        _assumeClean(relayer); // relayer must be able to receive funds
        commitDelay = commitDelay % FUZZ_TIME_PERIOD;
        vm.assume(commitDelay >= COMMIT_REPLAY_DELAY);
        vm.warp(block.timestamp + commitDelay); // block.timestamp must be at least greater than the replay delay

        // State: Trusted Registration is disabled in both registries, and trusted caller is not set
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        registerDelay = registerDelay % FUZZ_TIME_PERIOD;
        vm.assume(registerDelay > COMMIT_REGISTER_DELAY);

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + registerDelay);

        vm.deal(relayer, amount);
        vm.prank(relayer);
        bundleRegistry.register{value: amount}(alice, recovery, "alice", secret);

        _assertSuccessfulRegistration(alice, recovery);

        assertEq(relayer.balance, amount - nameRegistry.fee());
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    function testFuzzCannotRegisterIfIdRegistryEnabledNameRegistryDisabled(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret,
        uint256 timestamp,
        uint256 delay
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        _assumeClean(relayer); // relayer must be able to receive funds
        timestamp = timestamp % FUZZ_TIME_PERIOD;
        vm.assume(timestamp > COMMIT_REPLAY_DELAY);
        delay = delay % FUZZ_TIME_PERIOD;
        vm.assume(delay >= COMMIT_REGISTER_DELAY);

        vm.warp(timestamp); // block.timestamp must be at least greater than the replay delay

        // State: Trusted registration is enabled in IdRegistry, but disabled in NameRegistry and
        // trusted caller is set in IdRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + delay);

        vm.deal(relayer, 1 ether);
        vm.prank(relayer);
        vm.expectRevert(IdRegistry.Seedable.selector);
        bundleRegistry.register{value: 0.01 ether}(alice, recovery, "alice", secret);

        _assertUnsuccessfulRegistration(alice);

        assertEq(relayer.balance, 1 ether);
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    function testFuzzCannotRegisterIfIdRegistryDisabledNameRegistryEnabled(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        _assumeClean(relayer); // relayer must be able to receive funds
        vm.warp(COMMIT_REPLAY_DELAY + 1); // block.timestamp must be at least greater than the replay delay

        // State: Trusted registration is disabled in IdRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        vm.expectRevert(NameRegistry.Seedable.selector);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + COMMIT_REGISTER_DELAY);

        vm.deal(relayer, 1 ether);
        vm.prank(relayer);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        bundleRegistry.register{value: 1 ether}(alice, recovery, "alice", secret);

        _assertUnsuccessfulRegistration(alice);

        assertEq(relayer.balance, 1 ether);
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    function testFuzzCannotRegisterIfBothEnabled(
        address alice,
        address relayer,
        address recovery,
        bytes32 secret
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(relayer != address(bundleRegistry)); // the bundle registry cannot call itself
        _assumeClean(relayer); // relayer must be able to receive funds
        vm.warp(COMMIT_REPLAY_DELAY + 1); // block.timestamp must be at least greater than the replay delay

        // State: Trusted registration is enabled in both registries and trusted caller is set in both
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        // Commit must be made and waiting period must have elapsed before fname can be registered
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret, recovery);
        vm.expectRevert(NameRegistry.Seedable.selector);
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + COMMIT_REGISTER_DELAY);

        vm.deal(relayer, 1 ether);
        vm.prank(relayer);
        vm.expectRevert(IdRegistry.Seedable.selector);
        bundleRegistry.register{value: 1 ether}(alice, recovery, "alice", secret);

        _assertUnsuccessfulRegistration(alice);

        assertEq(relayer.balance, 1 ether);
        assertEq(address(bundleRegistry).balance, 0 ether);
    }

    /*//////////////////////////////////////////////////////////////
                     PARTIAL TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzPartialTrustedRegister(address alice, address recovery) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is disabled in IdRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        bundleRegistry.partialTrustedRegister(alice, recovery, "alice");

        _assertSuccessfulRegistration(alice, recovery);
    }

    function testFuzzCannotPartialTrustedRegisterIfBothEnabled(address alice, address recovery) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is enabled in both registries and trusted caller is set
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        vm.expectRevert(IdRegistry.Seedable.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzCannotPartialTrustedRegisterIfIdRegistryEnabledNameRegistryDisabled(
        address alice,
        address recovery
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is enabled in IdRegistry, but disabled in NameRegistry and
        // trusted caller is set in IdRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(IdRegistry.Seedable.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzCannotPartialTrustedRegisterIfBothDisabled(address alice, address recovery) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is disabled in both registries and trusted caller is not sset
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.NotSeedable.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzCannotPartialTrustedRegisterUnlessTrustedCaller(
        address alice,
        address recovery,
        address untrustedCaller
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(untrustedCaller != bundleRegistry.getTrustedCaller());

        // State: Trusted registration is disabled in IdRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        // Call is made from an address that is not address(this), since address(this) is the
        // deployer and therefore the trusted caller for BundleRegistry
        vm.prank(untrustedCaller);
        vm.expectRevert(BundleRegistry.Unauthorized.selector);
        bundleRegistry.partialTrustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedRegister(address alice, address recovery) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is enabled in both registries and trusted caller is set in both
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        bundleRegistry.trustedRegister(alice, recovery, "alice");

        _assertSuccessfulRegistration(alice, recovery);
    }

    function testFuzzCannotTrustedRegisterFromUntrustedCaller(
        address alice,
        address recovery,
        address untrustedCaller
    ) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(untrustedCaller != address(this)); // guarantees call from untrusted caller

        // State: Trusted registration is enabled in both registries and trusted caller is set in both
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        // Call is made from an address that is not address(this), since address(this) is the deployer
        // and therefore the trusted caller for BundleRegistry
        vm.prank(untrustedCaller);
        vm.expectRevert(BundleRegistry.Unauthorized.selector);
        bundleRegistry.trustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedRegisterIfIdRegistryDisabledNameRegistryEnabled(address alice, address recovery) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is disabled in IdRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.Registrable.selector);
        bundleRegistry.trustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedRegisterIfIdRegistryEnabledNameRegistryDisabled(address alice, address recovery) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is enabled in IdRegistry, but disabled in NameRegistry and
        // trusted caller is set in IdRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.NotSeedable.selector);
        bundleRegistry.trustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedRegisterIfBothDisabled(address alice, address recovery) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is disabled in both registries
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.expectRevert(NameRegistry.Registrable.selector);
        bundleRegistry.trustedRegister(alice, recovery, "alice");

        _assertUnsuccessfulRegistration(alice);
    }

    /*//////////////////////////////////////////////////////////////
                      TRUSTED BATCH REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedBatchRegister(address alice, address bob, address carol) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(bob != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(carol != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume((alice != bob) && (alice != carol) && (bob != carol));

        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        BundleRegistry.BatchUser[] memory batchArray = new BundleRegistry.BatchUser[](3);
        batchArray[0] = BundleRegistry.BatchUser({to: alice, username: "alice"});
        batchArray[1] = BundleRegistry.BatchUser({to: bob, username: "bob"});
        batchArray[2] = BundleRegistry.BatchUser({to: carol, username: "carol"});

        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, address(0));

        vm.expectEmit(true, true, true, true);
        emit Register(bob, 2, address(0));

        vm.expectEmit(true, true, true, true);
        emit Register(carol, 3, address(0));

        bundleRegistry.trustedBatchRegister(batchArray);

        // Check that alice was set up correctly
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        (address recoveryAlice, uint40 expiryTsAlice) = nameRegistry.metadataOf(ALICE_TOKEN_ID);
        assertEq(expiryTsAlice, block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(recoveryAlice, address(0));

        // Check that bob was set up correctly
        assertEq(idRegistry.idOf(bob), 2);
        assertEq(idRegistry.getRecoveryOf(2), address(0));
        assertEq(nameRegistry.balanceOf(bob), 1);
        (address recoveryBob, uint40 expiryTsBob) = nameRegistry.metadataOf(BOB_TOKEN_ID);
        assertEq(expiryTsBob, block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), bob);
        assertEq(recoveryBob, address(0));

        // Check that carol was set up correctly
        assertEq(idRegistry.idOf(carol), 3);
        assertEq(idRegistry.getRecoveryOf(3), address(0));
        assertEq(nameRegistry.balanceOf(carol), 1);
        (address recoveryCharlie, uint40 expiryTsCharlie) = nameRegistry.metadataOf(CAROL_TOKEN_ID);
        assertEq(expiryTsCharlie, block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.ownerOf(CAROL_TOKEN_ID), carol);
        assertEq(recoveryCharlie, address(0));
    }

    function testFuzzCannotTrustedBatchRegisterFromUntrustedCaller(address alice, address untrustedCaller) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT
        vm.assume(untrustedCaller != address(this)); // guarantees call from untrusted caller

        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        BundleRegistry.BatchUser[] memory batchArray = new BundleRegistry.BatchUser[](1);
        batchArray[0] = BundleRegistry.BatchUser({to: alice, username: "alice"});

        // Call is made from an address that is not address(this), since address(this) is the deployer
        // and therefore the trusted caller for BundleRegistry
        vm.prank(untrustedCaller);
        vm.expectRevert(BundleRegistry.Unauthorized.selector);
        bundleRegistry.trustedBatchRegister(batchArray);

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedBatchRegisterIfIdRegistryDisabledNameRegistryEnabled(address alice) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is disabled in IdRegistry, but enabled in NameRegistry and
        // trusted caller is set in NameRegistry
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(address(bundleRegistry));
        idRegistry.disableTrustedOnly();

        BundleRegistry.BatchUser[] memory batchArray = new BundleRegistry.BatchUser[](1);
        batchArray[0] = BundleRegistry.BatchUser({to: alice, username: "alice"});

        vm.expectRevert(NameRegistry.Registrable.selector);
        bundleRegistry.trustedBatchRegister(batchArray);

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedRegisterIfIdRegistryEnabledNameRegistryDisabled(address alice) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is enabled in IdRegistry, but disabled in NameRegistry and
        // trusted caller is set in IdRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        BundleRegistry.BatchUser[] memory batchArray = new BundleRegistry.BatchUser[](1);
        batchArray[0] = BundleRegistry.BatchUser({to: alice, username: "alice"});

        vm.expectRevert(NameRegistry.NotSeedable.selector);
        bundleRegistry.trustedBatchRegister(batchArray);

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedRegisterIfBothDisabled(address alice) public {
        vm.assume(alice != address(0)); // OZ's ERC-721 throws when a zero-address mints an NFT

        // State: Trusted registration is disabled in both registries
        idRegistry.disableTrustedOnly();
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        BundleRegistry.BatchUser[] memory batchArray = new BundleRegistry.BatchUser[](1);
        batchArray[0] = BundleRegistry.BatchUser({to: alice, username: "alice"});

        vm.expectRevert(NameRegistry.Registrable.selector);
        bundleRegistry.trustedBatchRegister(batchArray);

        _assertUnsuccessfulRegistration(alice);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeTrustedCaller(address alice) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        assertEq(bundleRegistry.owner(), owner);

        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedCaller(alice, address(this));
        bundleRegistry.changeTrustedCaller(alice);
        assertEq(bundleRegistry.getTrustedCaller(), alice);
    }

    function testFuzzCannotChangeTrustedCallerToZeroAddress(address alice) public {
        vm.assume(alice != FORWARDER);
        assertEq(bundleRegistry.owner(), owner);

        vm.expectRevert(BundleRegistry.InvalidAddress.selector);
        bundleRegistry.changeTrustedCaller(address(0));

        assertEq(bundleRegistry.getTrustedCaller(), owner);
    }

    function testFuzzCannotChangeTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != address(0));
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

        vm.assume(a > MAX_PRECOMPILE);
        vm.assume(a != ADMIN);
    }

    // Assert that a given fname was correctly registered with id 1 and recovery
    function _assertSuccessfulRegistration(address alice, address recovery) internal {
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        assertEq(nameRegistry.balanceOf(alice), 1);
        (address _recovery, uint40 expiryTs) = nameRegistry.metadataOf(ALICE_TOKEN_ID);
        assertEq(expiryTs, block.timestamp + REGISTRATION_PERIOD);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(_recovery, recovery);
    }

    // Assert that a given fname was not registered and the contracts have no registrations
    function _assertUnsuccessfulRegistration(address alice) internal {
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        assertEq(nameRegistry.balanceOf(alice), 0);
        (address recovery, uint40 expiryTs) = nameRegistry.metadataOf(ALICE_TOKEN_ID);
        assertEq(expiryTs, 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(recovery, address(0));
    }
}
