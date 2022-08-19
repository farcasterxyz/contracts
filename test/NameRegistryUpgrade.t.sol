// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

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

contract NameReg_istryUpgradeTest is Test {
    ERC1967Proxy proxy;
    NameRegistry nameRegistry;
    NameRegistry proxiedNameRegistry;
    NameRegistryV2 nameRegistryV2;
    NameRegistryV2 proxiedNameRegistryV2;

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

        // Cast the Proxy as a NameRegistry so we can call NameRegistry methods easily
        proxiedNameRegistry = NameRegistry(address(proxyAddr));
        proxiedNameRegistry.initialize("Farcaster NameRegistry", "FCN", owner, vault, preregistrar);
    }

    function testInitializeSetters() public {
        assertEq(proxiedNameRegistry.owner(), owner);
    }

    function testUpgrade() public {
        // 1. Calling a v2-only function on the proxy should revert before the upgrade is performed
        vm.expectRevert();
        (bool s1, ) = address(proxy).call(abi.encodeWithSelector(nameRegistryV2.setNumber.selector, 1));
        assertEq(s1, true);

        // 2. Call upgrade on the proxy, which swaps the v1 implementation for the v2 implementation, and then recast
        // the proxy as a NameRegistryV2
        vm.prank(owner);
        proxiedNameRegistry.upgradeTo(address(nameRegistryV2));
        proxiedNameRegistryV2 = NameRegistryV2(address(proxyAddr));

        // 3. Re-initialize the v2 contract
        vm.prank(owner);
        proxiedNameRegistryV2.initializeV2("Farcaster NameRegistry", "FCN", owner, vault, preregistrar);

        // 4. Assert that data stored when proxy was connected to v1 is present after being connected to v2
        assertEq(proxiedNameRegistryV2.vault(), vault);

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
    mapping(bytes32 => uint256) public timestampOf;
    mapping(uint256 => uint256) public expiryOf;
    uint256 internal _nextYearIdx;
    address private preregistrar;
    address public vault;
    uint256[] public _yearTimestamps;
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
        address _owner,
        address _vault,
        address _preregistrar
    ) public reinitializer(2) {
        __UUPSUpgradeable_init();

        __ERC721_init_unchained(_name, _symbol);

        // Initialize the owner to the deployer and then transfer it to _owner
        __Ownable_init_unchained();
        transferOwnership(_owner);

        vault = _vault;
        preregistrar = _preregistrar;

        _yearTimestamps = [
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
            // Safety: _nextYearIdx is always < _yearTimestamps.length which can't overflow when added to 2021
            if (block.timestamp < _yearTimestamps[_nextYearIdx]) {
                return _nextYearIdx + 2072;
            }

            uint256 length = _yearTimestamps.length;

            // Safety: _nextYearIdx is always < _yearTimestamps.length which can't overflow when added to 1
            for (uint256 i = _nextYearIdx + 1; i < length; ) {
                if (_yearTimestamps[i] > block.timestamp) {
                    // Slither false positive: https://github.com/crytic/slither/issues/1338
                    // slither-disable-next-line costly-loop
                    _nextYearIdx = i;
                    // Safety: _nextYearIdx is always <= _yearTimestamps.length which can't overflow when added to 2021
                    return _nextYearIdx + 2072;
                }

                // Safety: i cannot overflow because length is a pre-determined constant value.
                i++;
            }

            revert InvalidTime();
        }
    }
}
