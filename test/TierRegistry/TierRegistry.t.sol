// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {SafeERC20, IERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITierRegistry} from "../../src/TierRegistry.sol";
import {IGuardians} from "../../src/abstract/Guardians.sol";
import {IMigration} from "../../src/interfaces/abstract/IMigration.sol";
import {TransferHelper} from "../../src/libraries/TransferHelper.sol";
import {TierRegistryTestSuite} from "./TierRegistryTestSuite.sol";

contract TierRegistryTest is TierRegistryTestSuite {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PurchasedTier(uint256 indexed fid, uint256 indexed tier, uint256 forDays, address indexed payer);
    event DeactivateTier(uint256 indexed tier);
    event SetTier(
        uint256 indexed tier,
        uint256 minDays,
        uint256 maxDays,
        address vault,
        address paymentToken,
        uint256 tokenPricePerDay
    );
    event Migrated(uint256 indexed migratedAt);
    event SetMigrator(address oldMigrator, address newMigrator);
    event SweepToken(address indexed token, address to, uint256 balance);

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testVersion() public {
        assertEq(tierRegistry.VERSION(), "2025.06.16");
    }

    function testOwner() public {
        assertEq(tierRegistry.owner(), owner);
    }

    function testInitialGracePeriod() public {
        assertEq(tierRegistry.gracePeriod(), 1 days);
    }

    function testInitialMigrationTimestamp() public {
        assertEq(tierRegistry.migratedAt(), 0);
    }

    function testInitialMigrator() public {
        assertEq(tierRegistry.migrator(), migrator);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(tierRegistry.isMigrated(), false);
    }

    /*//////////////////////////////////////////////////////////////
                            PURCHASE TIER
    //////////////////////////////////////////////////////////////*/

    function testFuzzPurchaseTier(uint256 fid, uint64 price, uint64 forDays, address payer, address vault) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.assume(forDays != 0);
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        _purchaseTier(fid, tier, forDays, payer);
    }

    function testFuzzPurchaseTierWithNoTime(uint256 fid, uint64 price, address payer, address vault) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        tierRegistry.purchaseTier(fid, tier, 0);
    }

    function testFuzzPurchaseTierWhenPaused(
        uint256 fid,
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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
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
        vm.expectRevert(ITierRegistry.InvalidTier.selector);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }

    function testFuzzPurchaseRemovedTier(
        uint256 fid,
        uint64 price,
        uint64 forDays,
        address payer,
        address vault
    ) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        vm.assume(forDays != 0);
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.prank(owner);

        vm.expectEmit();
        emit DeactivateTier(tier);
        tierRegistry.deactivateTier(tier);

        vm.prank(payer);
        vm.expectRevert(ITierRegistry.InvalidTier.selector);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }

    function testFuzzPurchaseTierForTooMuchTime(uint256 fid, uint64 price, address payer, address vault) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, 300, vault);
        vm.prank(payer);
        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        tierRegistry.purchaseTier(fid, tier, 301);
    }

    function testFuzzPurchaseTierForTooLittleTime(uint256 fid, uint64 price, address payer, address vault) public {
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        uint256 tier = _addTier(address(token), price, 30, DEFAULT_MAX_DAYS, vault);
        vm.prank(payer);
        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        tierRegistry.purchaseTier(fid, tier, 29);
    }

    function testFuzzPurchaseTierWithInsufficientFunds(
        uint256 fid,
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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

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
        address payer,
        uint32 price,
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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        _batchPurchaseTier(tier, fids, forDays, payer);
    }

    function testFuzzBatchPurchaseTierWhilePaused(
        address payer,
        uint32 price,
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

        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.expectRevert("Pausable: paused");
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierZeroTimeCancelsBatch(
        address payer,
        uint32 price,
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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierTooLittleTimeCancelsBatch(
        address payer,
        uint32 price,
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
        uint256 tier = _addTier(address(token), price, minDays, DEFAULT_MAX_DAYS, vault);

        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierTooMuchTimeTimeCancelsBatch(
        address payer,
        uint32 price,
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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, maxDays, vault);

        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierZeroFids(
        address payer,
        uint32 price,
        address vault,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_forDays.length > 0);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        uint256[] memory fids = new uint256[](0);
        uint256[] memory forDays = new uint256[](_forDays.length);
        for (uint256 i; i < _forDays.length; ++i) {
            forDays[i] = _forDays[i];
        }

        vm.expectRevert(ITierRegistry.InvalidBatchInput.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierMismatchedInputs(
        address payer,
        uint32 price,
        address vault,
        uint256[] calldata _fids,
        uint16[] calldata _forDays
    ) public {
        vm.assume(_fids.length != _forDays.length);
        vm.assume(payer != address(0));
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        uint256[] memory forDays = new uint256[](_forDays.length);
        for (uint256 i; i < _forDays.length; ++i) {
            forDays[i] = _forDays[i];
        }
        vm.expectRevert(ITierRegistry.InvalidBatchInput.selector);
        tierRegistry.batchPurchaseTier(tier, _fids, forDays);
    }

    function testFuzzBatchPurchaseTierInvalidTier(
        uint256 tier,
        address payer,
        uint32 price,
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
        vm.expectRevert(ITierRegistry.InvalidTier.selector);
        tierRegistry.batchPurchaseTier(tier, fids, forDays);
    }

    function testFuzzBatchPurchaseTierRevertsWithInsufficientFunds(
        address payer,
        uint32 price,
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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

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
        address payer,
        uint32 price,
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
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

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

    /*//////////////////////////////////////////////////////////////
                            EDIT TIERS
    //////////////////////////////////////////////////////////////*/

    function testFuzzAddMultipleTiers(uint256 daysBound1, uint256 daysBound2, uint64 price, address vault) public {
        vm.assume(daysBound1 != 0);
        vm.assume(daysBound2 != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        (uint256 minDays, uint256 maxDays) =
            daysBound1 < daysBound2 ? (daysBound1, daysBound2) : (daysBound2, daysBound1);
        uint256 tier1 = _addTier(address(token), price, minDays, maxDays, vault);
        assertEq(tier1, 1);
        uint256 tier2 = _addTier(address(token), price, minDays, maxDays, vault);
        assertEq(tier2, 2);
    }

    function testFuzzSetTierInvalidToken(uint256 minDays, uint256 maxDays, uint64 price, address vault) public {
        vm.assume(minDays != 0);
        vm.assume(maxDays != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 tier = tierRegistry.nextTierId();
        vm.expectRevert(ITierRegistry.InvalidTokenAddress.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, address(0), minDays, maxDays, price, vault);
    }

    function testFuzzSetTierInvalidMinDays(address token, uint256 maxDays, uint64 price, address vault) public {
        vm.assume(token != address(0));
        vm.assume(maxDays != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 tier = tierRegistry.nextTierId();
        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, 0, maxDays, price, vault);
    }

    function testFuzzSetTierInvalidMaxDays(address token, uint256 minDays, uint64 price, address vault) public {
        vm.assume(token != address(0));
        vm.assume(minDays != 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 tier = tierRegistry.nextTierId();
        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, minDays, 0, price, vault);
    }

    function testFuzzSetTierReverseMinAndMaxDays(
        address token,
        uint256 daysBound1,
        uint256 daysBound2,
        uint64 price,
        address vault
    ) public {
        vm.assume(token != address(0));
        vm.assume(daysBound1 != 0);
        vm.assume(daysBound2 != 0);
        vm.assume(daysBound1 != daysBound2);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        (uint256 minDays, uint256 maxDays) =
            daysBound1 < daysBound2 ? (daysBound1, daysBound2) : (daysBound2, daysBound1);
        uint256 tier = tierRegistry.nextTierId();
        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, maxDays, minDays, price, vault);
    }

    function testFuzzSetTierInvalidPrice(address token, uint256 daysBound1, uint256 daysBound2, address vault) public {
        vm.assume(token != address(0));
        vm.assume(daysBound1 != 0);
        vm.assume(daysBound2 != 0);
        vm.assume(vault != address(0));

        uint256 tier = tierRegistry.nextTierId();
        vm.expectRevert(ITierRegistry.InvalidPrice.selector);
        vm.prank(owner);
        (uint256 minDays, uint256 maxDays) =
            daysBound1 < daysBound2 ? (daysBound1, daysBound2) : (daysBound2, daysBound1);
        tierRegistry.setTier(tier, token, minDays, maxDays, 0, vault);
    }

    function testFuzzSetTierInvalidVault(address token, uint256 daysBound1, uint256 daysBound2, uint64 price) public {
        vm.assume(token != address(0));
        vm.assume(daysBound1 != 0);
        vm.assume(daysBound2 != 0);
        vm.assume(price != 0);

        uint256 tier = tierRegistry.nextTierId();
        vm.expectRevert(ITierRegistry.InvalidVaultAddress.selector);
        vm.prank(owner);
        (uint256 minDays, uint256 maxDays) =
            daysBound1 < daysBound2 ? (daysBound1, daysBound2) : (daysBound2, daysBound1);
        tierRegistry.setTier(tier, token, minDays, maxDays, price, address(0));
    }

    function testFuzzSetTierInvalidTierId(
        uint256 tier,
        address token,
        uint256 daysBound1,
        uint256 daysBound2,
        uint64 price,
        address vault
    ) public {
        vm.assume(token != address(0));
        vm.assume(vault != address(0));
        vm.assume(daysBound1 != 0);
        vm.assume(daysBound2 != 0);
        vm.assume(price != 0);
        vm.assume(tier != tierRegistry.nextTierId());

        (uint256 minDays, uint256 maxDays) =
            daysBound1 < daysBound2 ? (daysBound1, daysBound2) : (daysBound2, daysBound1);

        vm.expectRevert(ITierRegistry.InvalidTier.selector);
        vm.prank(owner);
        tierRegistry.setTier(tier, token, minDays, maxDays, price, vault);
    }

    function testFuzzDeactivateInactiveTier(
        uint256 tier
    ) public {
        vm.expectRevert(ITierRegistry.InvalidTier.selector);
        vm.prank(owner);
        tierRegistry.deactivateTier(tier);
    }

    function testFuzzViewStateForInactiveTier(
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
        uint256 tier = _addTier(address(token), price, minDays, maxDays, vault);

        vm.expectEmit();
        emit DeactivateTier(tier);
        vm.prank(owner);
        tierRegistry.deactivateTier(tier);

        ITierRegistry.TierInfo memory tierInfo = tierRegistry.tierInfo(tier);
        assertEq(tierInfo.minDays, minDays);
        assertEq(tierInfo.maxDays, maxDays);
        assertEq(tierInfo.vault, vault);
        assertEq(tierInfo.tokenPricePerDay, price);
        assertEq(address(tierInfo.paymentToken), address(token));
        assert(!tierInfo.isActive);
    }

    function testFuzzOnlyOwnerCanAddTier(
        uint256 minDays,
        uint256 maxDays,
        uint64 price,
        address vault,
        address caller
    ) public {
        vm.assume(caller != owner);

        uint256 tier = tierRegistry.nextTierId();
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        tierRegistry.setTier(tier, address(token), minDays, maxDays, price, vault);
    }

    /*//////////////////////////////////////////////////////////////
                             PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyGuardianCanPause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IGuardians.OnlyGuardian.selector);
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

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function testFuzzGetPrice(uint64 price, address vault, uint64 forDays, address caller) public {
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
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
        vm.expectRevert(ITierRegistry.InvalidTier.selector);
        vm.prank(caller);
        tierRegistry.price(tier, forDays);
    }

    function testFuzzGetTierInfo(uint64 price, address vault, address caller) public {
        vm.assume(price != 0);
        vm.assume(vault != address(0));
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        vm.prank(caller);
        ITierRegistry.TierInfo memory tierInfo = tierRegistry.tierInfo(tier);
        assertEq(tierInfo.minDays, DEFAULT_MIN_DAYS);
        assertEq(tierInfo.maxDays, DEFAULT_MAX_DAYS);
        assertEq(tierInfo.vault, vault);
        assertEq(address(tierInfo.paymentToken), address(token));
        assertEq(tierInfo.tokenPricePerDay, price);
        assertEq(tierInfo.isActive, true);
    }

    function testFuzzGetTierInfoForInvalidTier(uint256 tier, address caller) public {
        vm.prank(caller);
        ITierRegistry.TierInfo memory tierInfo = tierRegistry.tierInfo(tier);
        assertEq(tierInfo.minDays, 0);
        assertEq(tierInfo.maxDays, 0);
        assertEq(tierInfo.vault, address(0));
        assertEq(address(tierInfo.paymentToken), address(0));
        assertEq(tierInfo.tokenPricePerDay, 0);
        assertEq(tierInfo.isActive, false);
    }

    /*//////////////////////////////////////////////////////////////
                             SET MIGRATOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzOwnerCanSetMigrator(
        address migrator
    ) public {
        address oldMigrator = tierRegistry.migrator();
        vm.prank(owner);
        tierRegistry.pause();

        vm.expectEmit();
        emit SetMigrator(oldMigrator, migrator);
        vm.prank(owner);
        tierRegistry.setMigrator(migrator);

        assertEq(tierRegistry.migrator(), migrator);
    }

    function testFuzzSetMigratorRevertsWhenMigrated(
        address migrator
    ) public {
        address oldMigrator = tierRegistry.migrator();
        vm.prank(owner);
        tierRegistry.pause();

        vm.prank(oldMigrator);
        tierRegistry.migrate();

        vm.prank(owner);
        vm.expectRevert(IMigration.AlreadyMigrated.selector);
        tierRegistry.setMigrator(migrator);

        assertEq(tierRegistry.migrator(), oldMigrator);
    }

    function testFuzzSetMigratorRevertsWhenUnpaused(
        address migrator
    ) public {
        address oldMigrator = tierRegistry.migrator();

        vm.expectRevert("Pausable: not paused");
        vm.prank(owner);
        tierRegistry.setMigrator(migrator);
        vm.stopPrank();

        assertEq(tierRegistry.migrator(), oldMigrator);
    }

    /*//////////////////////////////////////////////////////////////
                             BATCH CREDIT
    //////////////////////////////////////////////////////////////*/

    function testFuzzBatchCreditTier(uint32 price, address vault, uint256[] calldata fids, uint16 _forDays) public {
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 forDays = bound(_forDays, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS);

        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.prank(owner);
        tierRegistry.pause();

        _batchCreditTier(tier, fids, forDays, migrator);
    }

    function testFuzzBatchCreditTierWhenUnpaused(
        uint32 price,
        address vault,
        uint256[] calldata fids,
        uint16 _forDays
    ) public {
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 forDays = bound(_forDays, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS);

        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.expectRevert("Pausable: not paused");
        vm.prank(migrator);
        tierRegistry.batchCreditTier(tier, fids, forDays);
    }

    function testFuzzBatchCreditTierZeroTimeCancelsBatch(uint32 price, address vault, uint256[] calldata fids) public {
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.prank(owner);
        tierRegistry.pause();

        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        vm.prank(migrator);
        tierRegistry.batchCreditTier(tier, fids, 0);
    }

    function testFuzzBatchCreditTierTooLittleTimeCancelsBatch(
        uint32 price,
        address vault,
        uint256[] calldata fids
    ) public {
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 tier = _addTier(address(token), price, 2, DEFAULT_MAX_DAYS, vault);

        vm.prank(owner);
        tierRegistry.pause();

        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        vm.prank(migrator);
        tierRegistry.batchCreditTier(tier, fids, 1);
    }

    function testFuzzBatchCreditTierTooMuchTimeCancelsBatch(
        uint32 price,
        address vault,
        uint256[] calldata fids
    ) public {
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.prank(owner);
        tierRegistry.pause();

        vm.expectRevert(ITierRegistry.InvalidDuration.selector);
        vm.prank(migrator);
        tierRegistry.batchCreditTier(tier, fids, DEFAULT_MAX_DAYS + 1);
    }

    function testFuzzBatchCreditTierZeroFids(uint32 price, address vault, uint16 _forDays) public {
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 forDays = bound(_forDays, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS);
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);
        uint256[] memory fids = new uint256[](0);

        vm.prank(owner);
        tierRegistry.pause();

        vm.expectRevert(ITierRegistry.InvalidBatchInput.selector);
        vm.prank(migrator);
        tierRegistry.batchCreditTier(tier, fids, forDays);
    }

    function testFuzzBatchCreditTierInvalidTier(
        uint256 tier,
        uint32 price,
        address vault,
        uint256[] calldata fids,
        uint16 _forDays
    ) public {
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 forDays = bound(_forDays, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS);

        vm.prank(owner);
        tierRegistry.pause();

        vm.expectRevert(ITierRegistry.InvalidTier.selector);
        vm.prank(migrator);
        tierRegistry.batchCreditTier(tier, fids, forDays);
    }

    function testFuzzBatchCreditTierWhenMigrated(
        uint32 price,
        address vault,
        uint256[] calldata fids,
        uint16 _forDays,
        uint32 warpForward
    ) public {
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        vm.prank(owner);
        tierRegistry.pause();

        uint256 forDays = bound(_forDays, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS);
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.prank(migrator);
        tierRegistry.migrate();

        vm.warp(block.timestamp + tierRegistry.gracePeriod() + 1 + warpForward);

        vm.expectRevert(IMigration.PermissionRevoked.selector);
        vm.prank(migrator);
        tierRegistry.batchCreditTier(tier, fids, forDays);
    }

    function testFuzzBatchCreditTierUnauthorizedCaller(
        address caller,
        uint32 price,
        address vault,
        uint256[] calldata fids,
        uint16 _forDays
    ) public {
        vm.assume(caller != migrator);
        vm.assume(fids.length > 0);
        vm.assume(price != 0);
        vm.assume(vault != address(0));

        uint256 forDays = bound(_forDays, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS);
        uint256 tier = _addTier(address(token), price, DEFAULT_MIN_DAYS, DEFAULT_MAX_DAYS, vault);

        vm.prank(owner);
        tierRegistry.pause();

        vm.expectRevert(IMigration.OnlyMigrator.selector);
        vm.prank(caller);
        tierRegistry.batchCreditTier(tier, fids, forDays);
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzMigration(
        uint40 timestamp
    ) public {
        vm.assume(timestamp != 0);

        vm.prank(owner);
        tierRegistry.pause();

        vm.warp(timestamp);
        vm.expectEmit();
        emit Migrated(timestamp);
        vm.prank(migrator);
        tierRegistry.migrate();

        assertEq(tierRegistry.isMigrated(), true);
        assertEq(tierRegistry.migratedAt(), timestamp);
    }

    function testFuzzOnlyMigratorCanMigrate(
        address caller
    ) public {
        vm.assume(caller != migrator);

        vm.prank(owner);
        tierRegistry.pause();

        vm.prank(caller);
        vm.expectRevert(IMigration.OnlyMigrator.selector);
        tierRegistry.migrate();

        assertEq(tierRegistry.isMigrated(), false);
        assertEq(tierRegistry.migratedAt(), 0);
    }

    function testFuzzCannotMigrateTwice(
        uint40 timestamp
    ) public {
        vm.prank(owner);
        tierRegistry.pause();

        timestamp = uint40(bound(timestamp, 1, type(uint40).max));
        vm.warp(timestamp);
        vm.prank(migrator);
        tierRegistry.migrate();

        timestamp = uint40(bound(timestamp, timestamp, type(uint40).max));
        vm.expectRevert(IMigration.AlreadyMigrated.selector);
        vm.prank(migrator);
        tierRegistry.migrate();

        assertEq(tierRegistry.isMigrated(), true);
        assertEq(tierRegistry.migratedAt(), timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 RESCUE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRescueTokens(uint256 _amount, address to) public {
        vm.assume(to != address(0));
        vm.assume(to != address(tierRegistry));
        vm.assume(to != address(tokenSource));
        uint256 amount = bound(_amount, 1, token.totalSupply());

        vm.prank(tokenSource);
        token.transfer(address(tierRegistry), amount);

        assertEq(token.balanceOf(to), 0);

        vm.prank(owner);
        vm.expectEmit();
        emit SweepToken(address(token), to, amount);
        tierRegistry.sweepToken(address(token), to);

        assertEq(token.balanceOf(to), amount);
    }

    function testFuzzOnlyOwnerCanRescueTokens(address caller, address to) public {
        vm.assume(to != address(0));
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        tierRegistry.sweepToken(address(token), to);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

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

    function _addTier(
        address paymentToken,
        uint64 price,
        uint256 minDays,
        uint256 maxDays,
        address vault
    ) public returns (uint256) {
        uint256 tier = tierRegistry.nextTierId();
        vm.expectEmit();
        emit SetTier(tier, minDays, maxDays, vault, paymentToken, price);
        vm.prank(owner);
        tierRegistry.setTier(tier, paymentToken, minDays, maxDays, price, vault);
        assertEq(tierRegistry.nextTierId(), tier + 1);

        ITierRegistry.TierInfo memory tierInfo = tierRegistry.tierInfo(tier);
        assertEq(paymentToken, address(tierInfo.paymentToken));
        assertEq(price, tierInfo.tokenPricePerDay);
        assertEq(minDays, tierInfo.minDays);
        assertEq(maxDays, tierInfo.maxDays);
        assertEq(vault, tierInfo.vault);
        assert(tierInfo.isActive);
        return tier;
    }

    function _batchCreditTier(uint256 tier, uint256[] memory fids, uint256 numDays, address caller) public {
        // Expect emitted events
        for (uint256 i; i < fids.length; ++i) {
            vm.expectEmit();
            emit PurchasedTier(fids[i], tier, numDays, caller);
        }

        vm.prank(caller);
        tierRegistry.batchCreditTier(tier, fids, numDays);
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
            emit PurchasedTier(fids[i], tier, forDays[i], payer);
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
        emit PurchasedTier(fid, tier, forDays, payer);
        vm.prank(payer);
        tierRegistry.purchaseTier(fid, tier, forDays);
    }
}
