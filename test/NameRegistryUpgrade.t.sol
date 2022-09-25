// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

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
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistryProxy;
    NameRegistryV2 nameRegistryV2Impl;

    address defaultAdmin = address(this);

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);
    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    function setUp() public {
        nameRegistryImpl = new NameRegistry(FORWARDER);
        nameRegistryV2Impl = new NameRegistryV2(FORWARDER);
        proxy = new ERC1967Proxy(address(nameRegistryImpl), "");

        nameRegistryProxy = NameRegistry(address(proxy));
        nameRegistryProxy.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistryProxy.grantRole(ADMIN_ROLE, ADMIN);
    }

    function testProxyRead() public {
        // Check that values set in the initializer can be read from the proxy
        assertEq(nameRegistryProxy.vault(), VAULT);
    }

    function testV2Initializer(address newVault) public {
        // Check that upgrading and initializing changes storage values correctly
        assertEq(nameRegistryProxy.vault(), VAULT);

        NameRegistryV2 nameRegistryV2Proxy = _upgradeToV2();

        vm.prank(ADMIN);
        nameRegistryV2Proxy.initializeV2("Farcaster NameRegistry", "FCN", newVault, POOL);

        // Calling nameRegistryProxy and nameRegistryV2Proxy is equivalent on-chain, they're just
        // different solidity classes with the same address
        assertEq(nameRegistryProxy.vault(), newVault);
    }

    function testV2NewFunction() public {
        // Check that a new function added in V2 can be called
        NameRegistryV2 nameRegistryV2Proxy = _upgradeToV2();

        vm.prank(ADMIN);
        nameRegistryV2Proxy.initializeV2("Farcaster NameRegistry", "FCN", VAULT, POOL);

        assertEq(nameRegistryV2Proxy.number(), 0);

        nameRegistryV2Proxy.setNumber(42);
        assertEq(nameRegistryV2Proxy.number(), 42);
    }

    // solhint-disable-next-line no-empty-blocks
    function testModifiedFnAfterUpgrade() public {
        // TODO: If we decide to stick with UUPS, assert that a function can be redefined and will
        // execute its new logic when the proxy is called
    }

    // solhint-disable-next-line no-empty-blocks
    function testStorage() public {
        // TODO: If we decide to stick with UUPS, assert that all storage slots are preserved
        // on upgrade
    }

    function testCannotCallV2FunctionBeforeUpgrade() public {
        vm.expectRevert();
        (bool s1, ) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2Impl.setNumber.selector, 1));
        assertEq(s1, true);
    }

    function testCannotUpgradeUnlessOwner(address alice) public {
        vm.assume(alice != defaultAdmin && alice != ADMIN);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistryProxy.upgradeTo(address(nameRegistryV2Impl));
    }

    /// @dev Upgrade the proxy to the V2 implementation and return the proxy as a V2 contract instance
    function _upgradeToV2() public returns (NameRegistryV2) {
        vm.prank(ADMIN);
        nameRegistryProxy.upgradeTo(address(nameRegistryV2Impl));
        return NameRegistryV2(address(proxy));
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
}
