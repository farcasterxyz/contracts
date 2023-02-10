// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import "forge-std/Test.sol";

import "./TestConstants.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */
/* solhint-disable max-states-count */
/* solhint-disable avoid-low-level-calls */

contract NameRegistryBaseTest is Test {
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

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

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

    /// @dev vm.assume that the address does not match known contracts
    function _assumeClean(address a) internal {
        for (uint256 i = 0; i < knownContracts.length; i++) {
            vm.assume(a != knownContracts[i]);
        }

        vm.assume(a > MAX_PRECOMPILE);
        vm.assume(a != ADMIN);
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
