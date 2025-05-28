// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {TierRegistry} from "../../src/TierRegistry.sol";
import {TransferHelper} from "../../src/libraries/TransferHelper.sol";
import {TierRegistryTestSuite, TierRegistryHarness} from "./TierRegistryTestSuite.sol";
import {MockChainlinkFeed} from "../Utils.sol";

contract TierRegistryTest is TierRegistryTestSuite {
    using FixedPointMathLib for uint256;

    event PurchasedTier(uint256 indexed fid, uint256 tier, uint256 forDays);
    event SetVault(address oldVault, address newVault);
    event SetToken(address oldToken, address newToken);
    event SetTierPrice(uint256 tier, address token, uint256 oldPrice, uint256 newPrice);

    function testVersion() public {
        assertEq(tierRegistry.VERSION(), "2025.05.21");
    }

    function testRoles() public {
        assertEq(tierRegistry.ownerRoleId(), keccak256("OWNER_ROLE"));
        assertEq(tierRegistry.operatorRoleId(), keccak256("OPERATOR_ROLE"));
    }

    function testDefaultAdmin() public {
        assertTrue(tierRegistry.hasRole(tierRegistry.DEFAULT_ADMIN_ROLE(), roleAdmin));
    }

    function testFuzzPurchaseTier(uint256 fid, uint256 tier, uint256 price, uint256 forDays, address payer) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(forDays >= tierRegistry.minDays());
        vm.assume(forDays <= tierRegistry.maxDays());
        vm.assume(price < 1 << 20);
        _setPriceForTier(tier, price);
        _purchaseTier(fid, tier, forDays, payer);
    }

    function testFuzzSetVault(
        address newVault
    ) public {
        vm.assume(newVault != address(0));
        vm.expectEmit(false, false, false, true);
        emit SetVault(vault, newVault);

        vm.prank(owner);
        tierRegistry.setVault(newVault);

        assertEq(tierRegistry.vault(), newVault);
    }

    function testFuzzOnlyOwnerCanSetVault(address caller, address vault) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(TierRegistry.NotOwner.selector);
        tierRegistry.setVault(vault);
    }

    function testSetVaultCannotBeZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TierRegistry.InvalidAddress.selector);
        tierRegistry.setVault(address(0));
    }

    function testPauseUnpause() public {
        assertEq(tierRegistry.paused(), false);

        vm.prank(owner);
        tierRegistry.pause();

        assertEq(tierRegistry.paused(), true);

        vm.prank(owner);
        tierRegistry.unpause();

        assertEq(tierRegistry.paused(), false);
    }

    function testFuzzOnlyOwnerCanPause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(TierRegistry.NotOwner.selector);
        tierRegistry.pause();
    }

    function testFuzzOnlyOwnerCanUnpause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(TierRegistry.NotOwner.selector);
        tierRegistry.unpause();
    }

    function _setPriceForTier(uint256 tier, uint256 price) public {
        vm.deal(owner, 100_000);
        vm.expectEmit();
        uint256 oldPrice = tierRegistry.tokenPricePerDay(tier);
        emit SetTierPrice(tier, address(token), oldPrice, price);
        vm.prank(owner);
        tierRegistry.setTier(tier, price);
        assertEq(tierRegistry.tokenPricePerDay(tier), price);
    }

    function _purchaseTier(uint256 fid, uint256 tier, uint256 forDays, address payer) public {
        uint256 amount = tierRegistry.tokenPricePerDay(tier) * forDays;
        vm.assume(amount <= token.totalSupply());
        token.transfer(payer, amount);

        vm.deal(payer, 100_000);
        vm.prank(payer);
        token.approve(address(tierRegistry), amount);

        vm.expectEmit();
        emit PurchasedTier(fid, tier, forDays);
        tierRegistry.purchaseTier(fid, tier, forDays, payer);
    }
}
