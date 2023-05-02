// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "../TestConstants.sol";
import "./NameRegistryConstants.sol";

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NameRegistry} from "../../src/NameRegistry.sol";
import {NameRegistryHarness} from "../Utils.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";

/* solhint-disable state-visibility */

abstract contract NameRegistryTestSuite is TestSuiteSetup {
    /// Instance of the implementation contract
    NameRegistryHarness internal nameRegistryImpl;

    // Instance of the proxy contract
    ERC1967Proxy internal nameRegistryProxy;

    // Instance of the proxy contract cast as the implementation contract
    NameRegistryHarness internal nameRegistry;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address internal defaultAdmin = address(this);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        TestSuiteSetup.setUp();
        nameRegistryImpl = new NameRegistryHarness(FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistryHarness(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);
    }
    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Register the username @alice to the address on Jan 1, 2023
    function _register(address alice) internal {
        _register(alice, "alice");
    }

    /// @dev Register the username to the user address on Jan 1, 2023
    function _register(address user, bytes16 username) internal {
        _disableTrusted();

        vm.deal(user, 10_000 ether);
        vm.warp(JAN1_2023_TS);

        vm.startPrank(user);
        bytes32 commitHash = nameRegistry.generateCommit(username, user, "secret", address(0));
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + COMMIT_REVEAL_DELAY);

        nameRegistry.register{value: nameRegistry.fee()}(username, user, "secret", address(0));
        vm.stopPrank();
    }

    /// @dev vm.assume that the address are unique
    function _assumeUniqueAndClean(address[] memory addresses) internal {
        for (uint256 i = 0; i < addresses.length - 1; i++) {
            for (uint256 j = i + 1; j < addresses.length; j++) {
                vm.assume(addresses[i] != addresses[j]);
            }
            _assumeClean(addresses[i]);
        }
        _assumeClean(addresses[addresses.length - 1]);
    }

    /// @dev Helper that assigns the recovery address and then requests a recovery
    function _requestRecovery(address alice, address recovery) internal returns (uint256 requestTs) {
        return _requestRecovery(alice, ALICE_TOKEN_ID, recovery);
    }

    /// @dev Helper that assigns the recovery address and then requests a recovery
    function _requestRecovery(address user, uint256 tokenId, address recovery) internal returns (uint256 requestTs) {
        vm.prank(user);
        nameRegistry.changeRecoveryAddress(tokenId, recovery);
        assertEq(nameRegistry.recoveryOf(tokenId), recovery);
        assertEq(nameRegistry.recoveryTsOf(tokenId), 0);
        assertEq(nameRegistry.recoveryDestinationOf(tokenId), address(0));

        vm.prank(recovery);
        nameRegistry.requestRecovery(tokenId, recovery);
        assertEq(nameRegistry.recoveryOf(tokenId), recovery);
        assertEq(nameRegistry.recoveryTsOf(tokenId), block.timestamp);
        assertEq(nameRegistry.recoveryDestinationOf(tokenId), recovery);
        return block.timestamp;
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
