// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../NameRegistry/NameRegistryConstants.sol";
import "../TestConstants.sol";
import {BundleRegistryHarness} from "../Utils.sol";
import {IdRegistryHarness} from "../Utils.sol";

import {NameRegistry} from "../../src/NameRegistry.sol";

/* solhint-disable state-visibility */

abstract contract BundleRegistryTestSuite is Test {
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
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    // Ensures that a fuzzed address input does not match a known contract address
    function _assumeClean(address a) internal view {
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
