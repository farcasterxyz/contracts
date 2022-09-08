// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ContextUpgradeable} from "openzeppelin-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC721Upgradeable} from "openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC2771ContextUpgradeable} from "openzeppelin-upgradeable/contracts/metatx/ERC2771ContextUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

import "forge-std/Test.sol";

import "../src/NameRegistry.sol";

/* solhint-disable state-visibility*/
/* solhint-disable avoid-low-level-calls */

contract NameRegistryUpgradeTest is Test {
    ERC1967Proxy proxy;
    NameRegistry nameRegistry;
    NameRegistry proxiedNameRegistry;
    NameRegistryV2 nameRegistryV2;
    NameRegistryV2 proxiedNameRegistryV2;

    address defaultAdmin = address(this);

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);
    address private constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    function setUp() public {
        nameRegistry = new NameRegistry(FORWARDER);
        nameRegistryV2 = new NameRegistryV2(FORWARDER);
        proxy = new ERC1967Proxy(address(nameRegistry), "");

        proxiedNameRegistry = NameRegistry(address(proxy));
        proxiedNameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        proxiedNameRegistry.grantRole(ADMIN_ROLE, ADMIN);
    }

    function testInitializeSetters() public {
        // Check that values set in the initializer are persisted correctly
        assertEq(proxiedNameRegistry.vault(), VAULT);
    }

    function testUpgrade() public {
        // 1. Calling a v2-only function on the proxy should revert before the upgrade is performed
        vm.expectRevert();
        (bool s1, ) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2.setNumber.selector, 1));
        assertEq(s1, true);

        // 2. Call upgrade on the proxy, which swaps the v1 implementation for the v2 implementation, and then recast
        // the proxy as a NameRegistryV2
        vm.prank(ADMIN);
        proxiedNameRegistry.upgradeTo(address(nameRegistryV2));
        proxiedNameRegistryV2 = NameRegistryV2(address(proxy));

        // 3. Re-initialize the v2 contract
        vm.prank(ADMIN);
        proxiedNameRegistryV2.initializeV2("Farcaster NameRegistry", "FCN", VAULT, POOL);

        // 4. Assert that data stored when proxy was connected to v1 is present after being connected to v2
        assertEq(proxiedNameRegistryV2.vault(), VAULT);

        // 5. Assert that data can be retrieved and stored correctly using v2-only functions
        assertEq(proxiedNameRegistryV2.number(), 0);
        proxiedNameRegistryV2.setNumber(42);
        assertEq(proxiedNameRegistryV2.number(), 42);

        // 6. Assert that the new currYear() implementation works with the upgraded timestamps
        vm.warp(3158524800); // Sunday, February 2, 2070 0:00:00 GMT
        assertEq(proxiedNameRegistryV2.currYear(), 2072);

        // Works correctly for known year range [2073 - 2074]
        vm.warp(3284755200); // Tuesday, February 2, 2074 0:00:00 GMT
        assertEq(proxiedNameRegistryV2.currYear(), 2074);

        // Does not work after 2076
        vm.warp(3347827200); // Sunday, February 2, 2076 0:00:00 GMT
        vm.expectRevert(NameRegistryV2.InvalidTime.selector);
        assertEq(proxiedNameRegistryV2.currYear(), 0);
    }

    function testCannotUpgradeUnlessOwner(address alice) public {
        vm.assume(alice != defaultAdmin && alice != ADMIN);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        proxiedNameRegistry.upgradeTo(address(nameRegistryV2));
    }
}

/**
 * A minimal, upgraded version of NameRegistry used for tests until a real V2 is implemented.
 */
contract NameRegistryV2 is
    Initializable,
    ERC721Upgradeable,
    ERC2771ContextUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Errors: most are not used and omitted for brevity
    error InvalidTime();

    // Events: are not used and omitted for brevity

    // Storage: The layout (ordering of non-constant variables) is preserved exactly as in V1, with
    // new values added at the bottom
    uint256 public fee;
    address public trustedCaller;
    uint256 public trustedOnly;
    mapping(bytes32 => uint256) public timestampOf;
    mapping(uint256 => uint256) public expiryOf;
    address public vault;
    address public pool;
    uint256[] internal yearTimestamps;
    uint256 internal nextYearIdx;
    mapping(uint256 => address) public recoveryOf;
    mapping(uint256 => uint256) public recoveryClockOf;
    mapping(uint256 => address) public recoveryDestinationOf;

    // New storage values
    uint256 public number;

    // Constants: all unused constants are omitted
    string public constant BASE_URI = "http://www.farcaster.xyz/u/";

    // Constructor: must be implemented to match interface
    // solhint-disable-next-line no-empty-blocks
    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {}

    // Functions: all functions that were implemented are omitted for brevity, unless an abstract
    // interface requires us to reimplement them or we needed to add new functions for testing.

    function initializeV2(
        string memory _name,
        string memory _symbol,
        address _vault,
        address _pool
    ) public reinitializer(2) {
        __UUPSUpgradeable_init();

        __ERC721_init_unchained(_name, _symbol);

        // Initialize the owner to the deployer and then transfer it to _owner
        __Ownable_init_unchained();

        vault = _vault;

        pool = _pool;

        yearTimestamps = [
            3250454400, // 2073
            3281990400, // 2074
            3313526400 // 2075
        ];
    }

    function tokenURI(uint256 tokenId) public pure override returns (string memory) {
        return string(abi.encodePacked(BASE_URI, tokenId, ".json"));
    }

    function _msgSender()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        sender = ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // New function added for testing
    function setNumber(uint256 _number) public {
        number = _number;
    }

    // Reimplementing currYear with new logic
    function currYear() public returns (uint256 year) {
        unchecked {
            // Safety: nextYearIdx is always < yearTimestamps.length which can't overflow when added to 2021
            if (block.timestamp < yearTimestamps[nextYearIdx]) {
                return nextYearIdx + 2072;
            }

            uint256 length = yearTimestamps.length;

            // Safety: nextYearIdx is always < yearTimestamps.length which can't overflow when added to 1
            for (uint256 i = nextYearIdx + 1; i < length; ) {
                if (yearTimestamps[i] > block.timestamp) {
                    // Slither false positive: https://github.com/crytic/slither/issues/1338
                    // slither-disable-next-line costly-loop
                    nextYearIdx = i;
                    // Safety: nextYearIdx is always <= yearTimestamps.length which can't overflow when added to 2021
                    return nextYearIdx + 2072;
                }

                // Safety: i cannot overflow because length is a pre-determined constant value.
                i++;
            }

            revert InvalidTime();
        }
    }
}
