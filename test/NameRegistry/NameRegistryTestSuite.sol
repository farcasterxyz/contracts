// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import "../TestConstants.sol";
import "./NameRegistryConstants.sol";

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NameRegistry} from "../../src/NameRegistry.sol";
import {NameRegistryHarness} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract NameRegistryTestSuite is Test {
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

    // Known contracts that must not be made to call other contracts in tests
    address[] internal knownContracts = [
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

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
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

    /// @dev vm.assume that the address does not match known contracts
    function _assumeClean(address a) internal {
        for (uint256 i = 0; i < knownContracts.length; i++) {
            vm.assume(a != knownContracts[i]);
        }

        vm.assume(a > MAX_PRECOMPILE);
        vm.assume(a != ADMIN);
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
