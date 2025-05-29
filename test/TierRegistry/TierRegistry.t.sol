// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {TierRegistry} from "../../src/TierRegistry.sol";
import {TransferHelper} from "../../src/libraries/TransferHelper.sol";
import {TierRegistryTestSuite, TierRegistryHarness} from "./TierRegistryTestSuite.sol";
import "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TierRegistryTest is TierRegistryTestSuite {
    using SafeERC20 for IERC20;

    event PurchasedTier(uint256 indexed fid, uint256 indexed tier, uint256 forDays);
    event DeactivateTier(uint256 tier);
    event SetTier(
        uint256 tier, uint256 minDays, uint256 maxDays, address vault, address paymentToken, uint256 tokenPricePerDay
    );

    function testVersion() public {
        assertEq(tierRegistry.VERSION(), "2025.05.21");
    }

    function testFuzzPurchaseTier(uint256 fid, uint256 tier, uint256 price, uint256 forDays, address payer) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(price < 1 << 20);
        vm.assume(forDays >= DEFAULT_MIN_DAYS);
        vm.assume(forDays <= DEFAULT_MAX_DAYS);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, DEFAULT_VAULT);
        _purchaseTier(fid, tier, forDays, payer);
    }

    function testFuzzPurchaseTierWithNoTime(uint256 fid, uint256 tier, uint256 price, address payer) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0 && price < 1 << 20);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, DEFAULT_VAULT);
        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.purchaseTier(fid, tier, 0);
    }

    function testFuzzPurchaseUnregisteredTier(
        uint256 fid,
        uint256 tier,
        uint256 price,
        uint256 forDays,
        address payer
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price < 1 << 20);
        vm.assume(forDays >= DEFAULT_MIN_DAYS);
        vm.assume(forDays <= DEFAULT_MAX_DAYS);
        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidTier.selector);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }

    function testFuzzPurchaseRemovedTier(
        uint256 fid,
        uint256 tier,
        uint256 price,
        uint256 forDays,
        address payer
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(price < 1 << 20);
        vm.assume(forDays >= DEFAULT_MIN_DAYS);
        vm.assume(forDays <= DEFAULT_MAX_DAYS);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, DEFAULT_VAULT);
        vm.prank(owner);

        vm.expectEmit();
        emit DeactivateTier(tier);
        tierRegistry.deactivateTier(tier);

        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidTier.selector);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }

    function testFuzzPurchaseTierForTooMuchTime(uint256 fid, uint256 tier, uint256 price, address payer) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, DEFAULT_VAULT);
        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.purchaseTier(fid, tier, DEFAULT_MAX_DAYS + 1);
    }

    function testFuzzPurchaseTierForTooLittleTime(uint256 fid, uint256 tier, uint256 price, address payer) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, DEFAULT_VAULT);
        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.purchaseTier(fid, tier, DEFAULT_MIN_DAYS - 1);
    }

    function testFuzzPurchaseTierWithInsufficientFunds(
        uint256 fid,
        uint256 tier,
        uint256 price,
        uint256 forDays,
        address payer
    ) public {
        vm.assume(payer != address(0));
        vm.assume(payer != tokenSource);
        vm.assume(price != 0);
        vm.assume(price < 1 << 20);
        vm.assume(forDays >= DEFAULT_MIN_DAYS);
        vm.assume(forDays <= DEFAULT_MAX_DAYS);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, DEFAULT_VAULT);

        uint256 amount = tierRegistry.price(tier, forDays);
        vm.assume(amount < token.totalSupply());
        vm.prank(tokenSource);
        token.transfer(payer, amount - 1);
        vm.prank(payer);
        token.approve(address(tierRegistry), amount);

        vm.prank(payer);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tierRegistry.purchaseTier(fid, tier, forDays);
        // We shouldn't consume any of the payer's balance
        uint256 payerBalance = token.balanceOf(payer);
        assertEq(payerBalance, amount - 1);
    }

    function testFuzzPurchaseTierWithInsufficientApprovedFunds(
        uint256 fid,
        uint256 tier,
        uint256 price,
        uint256 forDays,
        address payer
    ) public {
        vm.assume(payer != address(0));
        vm.assume(payer != tokenSource);
        vm.assume(price != 0);
        vm.assume(price < 1 << 20);
        vm.assume(forDays >= DEFAULT_MIN_DAYS);
        vm.assume(forDays <= DEFAULT_MAX_DAYS);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, DEFAULT_VAULT);

        uint256 amount = tierRegistry.price(tier, forDays);
        vm.assume(amount < token.totalSupply());
        vm.prank(tokenSource);
        token.transfer(payer, amount);
        vm.deal(payer, 100_000); // gas
        vm.prank(payer);
        token.approve(address(tierRegistry), amount - 1);

        vm.prank(payer);
        vm.expectRevert("ERC20: insufficient allowance");
        tierRegistry.purchaseTier(fid, tier, forDays);
        // We shouldn't consume any of the payer's balance
        uint256 payerBalance = token.balanceOf(payer);
        assertEq(payerBalance, amount);
    }

    function testFuzzSetTierInvalidToken(
        uint256 tier,
        uint256 minDays,
        uint256 maxDays,
        uint256 price,
        address vault
    ) public {
        vm.assume(minDays != 0);
        vm.assume(maxDays != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.expectRevert(TierRegistry.InvalidAddress.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, address(0), price, minDays, maxDays, vault);
    }

    function testFuzzSetTierInvalidMinDays(
        address token,
        uint256 tier,
        uint256 maxDays,
        uint256 price,
        address vault
    ) public {
        vm.assume(token != address(0));
        vm.assume(maxDays != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, price, 0, maxDays, vault);
    }

    function testFuzzSetTierInvalidMaxDays(
        address token,
        uint256 tier,
        uint256 minDays,
        uint256 price,
        address vault
    ) public {
        vm.assume(token != address(0));
        vm.assume(minDays != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, price, minDays, 0, vault);
    }

    function testFuzzSetTierInvalidPrice(
        address token,
        uint256 tier,
        uint256 minDays,
        uint256 maxDays,
        address vault
    ) public {
        vm.assume(token != address(0));
        vm.assume(minDays != 0);
        vm.assume(maxDays != 0);
        vm.assume(vault != address(0));
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, minDays, maxDays, 0, vault);
    }

    function testFuzzSetTierInvalidVault(
        address token,
        uint256 tier,
        uint256 minDays,
        uint256 maxDays,
        uint256 price
    ) public {
        vm.assume(token != address(0));
        vm.assume(minDays != 0);
        vm.assume(maxDays != 0);
        vm.assume(price != 0);
        vm.expectRevert(TierRegistry.InvalidAddress.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, minDays, maxDays, price, address(0));
    }

    function testFuzzDeactivateInactiveTier(
        uint256 tier
    ) public {
        vm.expectRevert(TierRegistry.InvalidTier.selector);
        vm.prank(owner);
        tierRegistry.deactivateTier(tier);
    }

    function testFuzzViewStateForInactiveTier(
        uint256 tier,
        uint256 minDays,
        uint256 maxDays,
        uint256 price,
        address vault
    ) public {
        vm.assume(price != 0);
        vm.assume(minDays != 0);
        vm.assume(maxDays != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, minDays, maxDays, vault);

        vm.expectEmit();
        emit DeactivateTier(tier);
        vm.prank(owner);
        tierRegistry.deactivateTier(tier);

        (
            uint256 tierMinDays,
            uint256 tierMaxDays,
            address tierVault,
            IERC20 paymentToken,
            uint256 tierPrice,
            bool isActive
        ) = tierRegistry.tierInfoByTier(tier);
        assertEq(tierMinDays, minDays);
        assertEq(tierMaxDays, maxDays);
        assertEq(tierVault, vault);
        assertEq(tierPrice, price);
        assertEq(address(paymentToken), address(token));
        assert(!isActive);
    }

    function testFuzzOnlyOwnerCanAdjustTiers(
        uint256 tier,
        uint256 minDays,
        uint256 maxDays,
        uint256 price,
        address vault,
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        tierRegistry.setTier(tier, address(token), minDays, maxDays, price, vault);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        tierRegistry.deactivateTier(tier);
    }

    function testFuzzOnlyOwnerCanPause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        tierRegistry.pause();
    }

    function testFuzzOnlyOwnerCanUnpause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        tierRegistry.unpause();
    }

    function _setTier(
        uint256 tier,
        address paymentToken,
        uint256 price,
        uint256 minDays,
        uint256 maxDays,
        address vault
    ) public {
        vm.expectEmit();
        emit SetTier(tier, minDays, maxDays, vault, paymentToken, price);
        vm.prank(owner);
        tierRegistry.setTier(tier, paymentToken, minDays, maxDays, price, vault);
        (
            uint256 newMinDays,
            uint256 newMaxDays,
            address newVault,
            IERC20 newPaymentToken,
            uint256 newPrice,
            bool newIsActive
        ) = tierRegistry.tierInfoByTier(tier);
        assertEq(paymentToken, address(newPaymentToken));
        assertEq(price, newPrice);
        assertEq(minDays, newMinDays);
        assertEq(maxDays, newMaxDays);
        assertEq(vault, newVault);
        assert(newIsActive);
    }

    function _purchaseTier(uint256 fid, uint256 tier, uint256 forDays, address payer) public {
        uint256 amount = tierRegistry.price(tier, forDays);
        vm.assume(amount <= token.totalSupply());
        vm.prank(tokenSource);
        token.transfer(payer, amount);

        vm.deal(payer, 100_000);
        vm.prank(payer);
        token.approve(address(tierRegistry), amount);

        vm.expectEmit();
        emit PurchasedTier(fid, tier, forDays);
        vm.prank(payer);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }
}
