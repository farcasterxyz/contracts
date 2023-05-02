// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../NameRegistry/NameRegistryConstants.sol";
import "../TestConstants.sol";

import {BundleRegistryHarness} from "../Utils.sol";
import {IdRegistryHarness} from "../Utils.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";

import {NameRegistry} from "../../src/NameRegistry.sol";

/* solhint-disable state-visibility */

abstract contract BundleRegistryTestSuite is TestSuiteSetup {
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

    function setUp() public override {
        TestSuiteSetup.setUp();

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
