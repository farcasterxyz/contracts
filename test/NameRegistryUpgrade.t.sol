// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "../src/NameRegistry.sol";

import {ContextUpgradeable} from "openzeppelin-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ERC721Upgradeable} from "openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC2771ContextUpgradeable} from "openzeppelin-upgradeable/contracts/metatx/ERC2771ContextUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* solhint-disable state-visibility*/
/* solhint-disable avoid-low-level-calls */

contract NameRegistryUpgradeTest is Test {
    ERC1967Proxy proxy;
    NameRegistry nameRegistry;
    NameRegistryV2 nameRegistryV2;

    address proxyAddr;
    address owner = address(0x123);
    address vault = address(0x456);
    address preregistrar = address(0x789);

    address private trustedForwarder = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);

    function setUp() public {
        nameRegistry = new NameRegistry(trustedForwarder);
        nameRegistryV2 = new NameRegistryV2(trustedForwarder);

        proxy = new ERC1967Proxy(address(nameRegistry), "");
        proxyAddr = address(proxy);

        (bool s, ) = address(proxy).call(
            abi.encodeWithSelector(
                nameRegistry.initialize.selector,
                "Farcaster NameRegistry",
                "FCN",
                owner,
                vault,
                preregistrar
            )
        );

        assertEq(s, true);
    }

    function testInitializeSetters() public {
        (, bytes memory returnedData) = address(proxy).call(abi.encodeWithSelector(nameRegistry.owner.selector));
        address returnedOwner = abi.decode(returnedData, (address));
        assertEq(returnedOwner, owner);
    }

    function testUpgrade() public {
        // 1. Calling a v2-only function from the v1 contract should revert
        vm.expectRevert();
        (bool s1, ) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2.setNumber.selector, 1));
        assertEq(s1, true);

        // 2. Upgrade the proxy to point to the v2 implementation
        vm.prank(owner);
        (bool s2, ) = address(proxy).call(
            abi.encodeWithSelector(nameRegistry.upgradeTo.selector, address(nameRegistryV2))
        );
        assertEq(s2, true);

        // 3. Assert that data stored when proxy was connected to v1 is present after being connected to v2
        (, bytes memory vaultData) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2.vault.selector));
        assertEq(abi.decode(vaultData, (address)), vault);

        // 4. Assert that data can be retrieved and stored correctly using v2-only functions
        (, bytes memory num1) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2.number.selector));
        assertEq(abi.decode(num1, (uint256)), 0);

        (bool s, ) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2.setNumber.selector, 42));
        assertEq(s, true);

        (, bytes memory num2) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2.number.selector));
        assertEq(abi.decode(num2, (uint256)), 42);
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
    // Events: are not used and omitted for brevity

    // Storage: The layout (ordering of non-constant variables) is preserved exactly as in V1, with
    // new values added at the bottom
    mapping(bytes32 => uint256) public timestampOf;
    mapping(uint256 => uint256) public expiryOf;
    uint256 internal _nextYearIdx;
    address private preregistrar;
    address public vault;
    uint256[] internal _yearTimestamps;
    mapping(uint256 => address) public recoveryOf;
    mapping(uint256 => uint256) public recoveryClockOf;
    mapping(uint256 => address) public recoveryDestinationOf;
    // New storage value added for testing
    uint256 public number;

    // Constants: all unused constants are omitted
    string public constant BASE_URI = "http://www.farcaster.xyz/u/";

    // Constructor: must be implemented to match interface
    // solhint-disable-next-line no-empty-blocks
    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {}

    // Functions: all functions that were implemented are omitted for brevity, unless an abstract
    // interface requires us to reimplement them or we needed to add new functions for testing.

    function initialize(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _vault,
        address _preregistrar
    ) public initializer {
        __UUPSUpgradeable_init();

        __ERC721_init_unchained(_name, _symbol);

        // Initialize the owner to the deployer and then transfer it to _owner
        __Ownable_init_unchained();
        transferOwnership(_owner);

        vault = _vault;
        preregistrar = _preregistrar;
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
