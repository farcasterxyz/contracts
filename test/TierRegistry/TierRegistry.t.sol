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
    event RemoveTier(uint256 tier);
    event SetTier(
        uint256 tier, uint256 minDays, uint256 maxDays, address vault, address paymentToken, uint256 tokenPricePerDay
    );

    function testVersion() public {
        assertEq(tierRegistry.VERSION(), "2025.05.21");
    }

    function testRoles() public {
        assertEq(tierRegistry.ownerRoleId(), keccak256("OWNER_ROLE"));
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

    function _setTier(
        uint256 tier,
        address paymentToken,
        uint256 price,
        uint256 minDays,
        uint256 maxDays,
        address vault
    ) public {
        vm.deal(owner, 100_000);
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
        (,,,, uint256 pricePerDay,) = tierRegistry.tierInfoByTier(tier);
        uint256 amount = pricePerDay * forDays;
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
