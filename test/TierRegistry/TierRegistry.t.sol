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

    function testFuzzPurchaseTier(
        uint256 fid,
        uint256 tier,
        uint64 price,
        uint64 forDays,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.assume(forDays != 0);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        _purchaseTier(fid, tier, forDays, payer);
    }

    function testFuzzPurchaseTierWithNoTime(
        uint256 fid,
        uint256 tier,
        uint64 price,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.purchaseTier(fid, tier, 0);
    }

    function testFuzzPurchaseTierWhenPaused(
        uint256 fid,
        uint256 tier,
        uint64 price,
        uint64 forDays,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(vault != address(0));
        vm.assume(price != 0);
        vm.assume(forDays != 0);
        vm.prank(owner);
        tierRegistry.pause();
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.prank(payer);
        vm.expectRevert("Pausable: paused");
        tierRegistry.purchaseTier(fid, tier, forDays);
    }

    function testFuzzPurchaseUnregisteredTier(
        uint256 fid,
        uint256 tier,
        uint64 price,
        uint64 forDays,
        address payer
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(forDays != 0);
        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidTier.selector);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }

    function testFuzzPurchaseRemovedTier(
        uint256 fid,
        uint256 tier,
        uint64 price,
        uint64 forDays,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.assume(forDays != 0);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.prank(owner);

        vm.expectEmit();
        emit DeactivateTier(tier);
        tierRegistry.deactivateTier(tier);

        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidTier.selector);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }

    function testFuzzPurchaseTierForTooMuchTime(
        uint256 fid,
        uint256 tier,
        uint64 price,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, 300, vault);
        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.purchaseTier(fid, tier, 301);
    }

    function testFuzzPurchaseTierForTooLittleTime(
        uint256 fid,
        uint256 tier,
        uint64 price,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, 30, DEFAULT_MAX_DAYS, vault);
        vm.prank(payer);
        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.purchaseTier(fid, tier, 29);
    }

    function testFuzzPurchaseTierWithInsufficientFunds(
        uint256 fid,
        uint256 tier,
        uint64 price,
        uint64 forDays,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(payer != tokenSource);
        vm.assume(price != 0);
        vm.assume(forDays != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

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
        uint64 price,
        uint64 forDays,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(payer != tokenSource);
        vm.assume(price != 0);
        vm.assume(forDays != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

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

    function testFuzzBatchPurchaseTier(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length > 0);
        vm.assume(_forDays.length > 0);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        _batchPurchaseTier(tier, fids, forDays, payer);
    }

    function testFuzzBatchPurchaseTierWhilePaused(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length > 3);
        vm.assume(_forDays.length > 3);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);

        vm.prank(owner);
        tierRegistry.pause();

        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.expectRevert("Pausable: paused");
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierZeroTimeCancelsBatch(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length > 3);
        vm.assume(_forDays.length > 3);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);
        // Create a 0 case
        forDays[0] = 0;
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierTooLittleTimeCancelsBatch(
        uint256 tier,
        address payer,
        uint64 price,
        uint64 minDays,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length > 3);
        vm.assume(_forDays.length > 3);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.assume(minDays > 1);
        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);
        // Create a 0 case
        forDays[0] = minDays - 1;
        _setTier(tier, address(token), price, minDays, DEFAULT_MAX_DAYS, vault);

        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierTooMuchTimeTimeCancelsBatch(
        uint256 tier,
        address payer,
        uint64 price,
        uint8 maxDays,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length > 3);
        vm.assume(_forDays.length > 3);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.assume(maxDays > 1);
        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);
        // Create a 0 case
        forDays[0] = uint16(maxDays) + 1;
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, maxDays, vault);

        vm.expectRevert(TierRegistry.InvalidAmount.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierZeroFids(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_forDays.length > 0);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        uint256[] memory fids = new uint256[](0);
        uint256[] memory forDays = new uint256[](_forDays.length);
        for (uint256 i; i < _forDays.length; ++i) {
            forDays[i] = _forDays[i];
        }

        vm.expectRevert(TierRegistry.InvalidBatchInput.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierMismatchedInputs(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length != _forDays.length);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        uint256[] memory forDays = new uint256[](_forDays.length);
        for (uint256 i; i < _forDays.length; ++i) {
            forDays[i] = _forDays[i];
        }
        vm.expectRevert(TierRegistry.InvalidBatchInput.selector);
        tierRegistry.batchPurchaseTier(tier, _fids, forDays);
    }

    function testFuzzBatchPurchaseTierInvalidTier(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length != 0);
        vm.assume(_forDays.length != 0);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);
        vm.expectRevert(TierRegistry.InvalidTier.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierRevertsWithInsufficientFunds(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length != 0);
        vm.assume(_forDays.length != 0);
        vm.assume(payer != address(0) && payer != tokenSource);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        uint256 totalTime;
        for (uint256 i; i < fids.length; ++i) {
            totalTime += forDays[i];
        }

        uint256 totalCost = tierRegistry.price(tier, totalTime);

        vm.assume(totalCost != 0);
        vm.assume(totalCost <= token.totalSupply());

        vm.prank(tokenSource);
        token.transfer(payer, totalCost - 1);

        vm.prank(payer);
        token.approve(address(tierRegistry), totalCost);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(payer);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);

        // We shouldn't consume any of the payer's balance
        uint256 payerBalance = token.balanceOf(payer);
        assertEq(payerBalance, totalCost - 1);
    }

    function testFuzzBatchPurchaseTierRevertsWithInsufficientApprovedFunds(
        uint256 tier,
        address payer,
        uint64 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length != 0);
        vm.assume(_forDays.length != 0);
        vm.assume(payer != address(0) && payer != tokenSource);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        (uint256[] memory fids, uint256[] memory forDays) = _normalizeBatchInputs(_fids, _forDays);
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        uint256 totalTime;
        for (uint256 i; i < fids.length; ++i) {
            totalTime += forDays[i];
        }

        uint256 totalCost = tierRegistry.price(tier, totalTime);

        vm.assume(totalCost != 0);
        vm.assume(totalCost <= token.totalSupply());

        vm.prank(tokenSource);
        token.transfer(payer, totalCost);

        vm.prank(payer);
        token.approve(address(tierRegistry), totalCost - 1);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(payer);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);

        // We shouldn't consume any of the payer's balance
        uint256 payerBalance = token.balanceOf(payer);
        assertEq(payerBalance, totalCost);
    }

    function testFuzzSetTierInvalidToken(
        uint256 tier,
        uint256 minDays,
        uint256 maxDays,
        uint64 price,
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
        uint64 price,
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
        uint64 price,
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
        uint256 daysBound1,
        uint256 daysBound2,
        uint64 price
    ) public {
        vm.assume(token != address(0));
        vm.assume(daysBound1 != 0);
        vm.assume(daysBound2 != 0);
        vm.assume(price != 0);
        vm.expectRevert(TierRegistry.InvalidAddress.selector);
        vm.prank(owner);
        (uint256 minDays, uint256 maxDays) =
            daysBound1 < daysBound2 ? (daysBound1, daysBound2) : (daysBound2, daysBound1);
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
        uint256 daysBound1,
        uint256 daysBound2,
        uint64 price,
        address vault
    ) public {
        vm.assume(price != 0);
        vm.assume(daysBound1 != 0);
        vm.assume(daysBound2 != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        (uint256 minDays, uint256 maxDays) =
            daysBound1 < daysBound2 ? (daysBound1, daysBound2) : (daysBound2, daysBound1);
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
        uint64 price,
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

    function testFuzzGetPrice(uint256 tier, uint64 price, address vault, uint64 forDays, address caller) public {
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.prank(caller);
        uint256 totalPrice = tierRegistry.price(tier, forDays);
        assertEq(totalPrice, uint256(forDays) * uint256(price));
    }

    function testFuzzGetPriceForInvalidTier(
        uint256 tier,
        uint64 price,
        address vault,
        uint64 forDays,
        address caller
    ) public {
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.expectRevert(TierRegistry.InvalidTier.selector);
        vm.prank(caller);
        tierRegistry.price(tier, forDays);
    }

    function testFuzzGetTierInfo(uint256 tier, uint64 price, address vault, uint64 forDays, address caller) public {
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        _setTier(tier, address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.prank(caller);
        TierRegistry.TierInfo memory tierInfo = tierRegistry.tierInfo(tier);
        assertEq(tierInfo.minDays, DEFAULT_MIN_DAYS);
        assertEq(tierInfo.maxDays, DEFAULT_MAX_DAYS);
        assertEq(tierInfo.vault, vault);
        assertEq(address(tierInfo.paymentToken), address(token));
        assertEq(tierInfo.tokenPricePerDay, price);
        assertEq(tierInfo.isActive, true);
    }

    function testFuzzGetTierInfoForInvalidTier(uint256 tier, uint64 forDays, address caller) public {
        vm.prank(caller);
        TierRegistry.TierInfo memory tierInfo = tierRegistry.tierInfo(tier);
        assertEq(tierInfo.minDays, 0);
        assertEq(tierInfo.maxDays, 0);
        assertEq(tierInfo.vault, address(0));
        assertEq(address(tierInfo.paymentToken), address(0));
        assertEq(tierInfo.tokenPricePerDay, 0);
        assertEq(tierInfo.isActive, false);
    }

    function _normalizeBatchInputs(
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public pure returns (uint256[] memory, uint256[] memory) {
        // Fuzzed dynamic arrays have a fuzzed length up to 256 elements.
        // Truncate the longer one so their lengths match.
        uint256 length = _fids.length <= _forDays.length ? _fids.length : _forDays.length;
        uint256[] memory fids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            fids[i] = _fids[i];
        }
        uint256[] memory forDays = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            forDays[i] = uint256(_forDays[i]) + 1;
        }
        return (fids, forDays);
    }

    function _setTier(
        uint256 tier,
        address paymentToken,
        uint64 price,
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

    function _batchPurchaseTier(uint256 tier, uint256[] memory fids, uint256[] memory forDays, address payer) public {
        uint256 totalTime;
        for (uint256 i; i < fids.length; ++i) {
            totalTime += forDays[i];
        }
        uint256 totalCost = tierRegistry.price(tier, totalTime);
        vm.assume(totalCost <= token.totalSupply());

        vm.prank(tokenSource);
        token.transfer(payer, totalCost);

        vm.prank(payer);
        token.approve(address(tierRegistry), totalCost);

        // Expect emitted events
        for (uint256 i; i < fids.length; ++i) {
            vm.expectEmit();
            emit PurchasedTier(fids[i], tier, forDays[i]);
        }

        vm.prank(payer);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function _purchaseTier(uint256 fid, uint256 tier, uint256 forDays, address payer) public {
        uint256 amount = tierRegistry.price(tier, forDays);
        vm.assume(amount <= token.totalSupply());
        vm.prank(tokenSource);
        token.transfer(payer, amount);

        vm.prank(payer);
        token.approve(address(tierRegistry), amount);

        vm.expectEmit();
        emit PurchasedTier(fid, tier, forDays);
        vm.prank(payer);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }
}
