// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Migration} from "./abstract/Migration.sol";
import {SafeERC20, IERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITierRegistry} from "./interfaces/ITierRegistry.sol";

/**
 * @title Farcaster TierRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract TierRegistry is ITierRegistry, Migration {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    string public constant VERSION = "2025.06.16";

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Maps tier IDs to their corresponding configuration data
     *      including payment parameters, duration limits,
     *      and activation status.
     * @custom:param tierId The unique identifier for the tier
     */
    mapping(uint256 tierId => TierInfo info) internal _tierInfoByTier;

    /**
     * @inheritdoc ITierRegistry
     */
    uint256 public nextTierId = 1;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the initial parameters and pause the contract.
     *
     * @param _migrator                      Migrator address.
     * @param _initialOwner                  Initial owner address.
     */
    constructor(address _migrator, address _initialOwner) Migration(24 hours, _migrator, _initialOwner) {}

    /*//////////////////////////////////////////////////////////////
                              VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    function price(uint256 tier, uint256 forDays) external view returns (uint256) {
        TierInfo memory info = _tierInfoByTier[tier];
        if (!info.isActive) revert InvalidTier();
        return info.tokenPricePerDay * forDays;
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function tierInfo(
        uint256 tier
    ) external view returns (TierInfo memory) {
        return _tierInfoByTier[tier];
    }

    /*//////////////////////////////////////////////////////////////
                        TIER PURCHASING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    function purchaseTier(uint256 fid, uint256 tier, uint256 forDays) external whenNotPaused {
        TierInfo memory info = _tierInfoByTier[tier];
        if (forDays == 0) revert InvalidDuration();
        if (!info.isActive) revert InvalidTier();
        if (forDays < info.minDays) revert InvalidDuration();
        if (forDays > info.maxDays) revert InvalidDuration();

        uint256 cost = info.tokenPricePerDay * forDays;

        emit PurchasedTier(fid, tier, forDays, msg.sender);

        info.paymentToken.safeTransferFrom(msg.sender, info.vault, cost);
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function batchPurchaseTier(
        uint256 tier,
        uint256[] calldata fids,
        uint256[] calldata forDays
    ) external whenNotPaused {
        if (fids.length == 0) revert InvalidBatchInput();
        if (fids.length != forDays.length) revert InvalidBatchInput();

        TierInfo memory info = _tierInfoByTier[tier];
        if (!info.isActive) revert InvalidTier();

        uint256 totalCost;
        for (uint256 i; i < fids.length; ++i) {
            uint256 numDays = forDays[i];
            if (numDays == 0) revert InvalidDuration();
            if (numDays < info.minDays) revert InvalidDuration();
            if (numDays > info.maxDays) revert InvalidDuration();
            totalCost += info.tokenPricePerDay * numDays;
            emit PurchasedTier(fids[i], tier, forDays[i], msg.sender);
        }

        info.paymentToken.safeTransferFrom(msg.sender, info.vault, totalCost);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    function batchCreditTier(uint256 tier, uint256[] calldata fids, uint256 forDays) external onlyMigrator {
        if (fids.length == 0) revert InvalidBatchInput();

        TierInfo memory info = _tierInfoByTier[tier];
        if (!info.isActive) revert InvalidTier();

        for (uint256 i; i < fids.length; ++i) {
            if (forDays == 0) revert InvalidDuration();
            if (forDays < info.minDays) revert InvalidDuration();
            if (forDays > info.maxDays) revert InvalidDuration();
            emit PurchasedTier(fids[i], tier, forDays, msg.sender);
        }
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function setTier(
        uint256 tier,
        address paymentToken,
        uint256 minDays,
        uint256 maxDays,
        uint256 tokenPricePerDay,
        address vault
    ) external onlyOwner {
        if (paymentToken == address(0)) revert InvalidTokenAddress();
        if (minDays == 0) revert InvalidDuration();
        if (maxDays == 0) revert InvalidDuration();
        if (minDays > maxDays) revert InvalidDuration();
        if (tokenPricePerDay == 0) revert InvalidPrice();
        if (vault == address(0)) revert InvalidVaultAddress();
        if (tier == 0) revert InvalidTier();
        if (tier > nextTierId) revert InvalidTier();

        emit SetTier(tier, minDays, maxDays, vault, paymentToken, tokenPricePerDay);

        _tierInfoByTier[tier] = TierInfo({
            minDays: minDays,
            maxDays: maxDays,
            paymentToken: IERC20(paymentToken),
            tokenPricePerDay: tokenPricePerDay,
            vault: vault,
            isActive: true
        });

        if (tier == nextTierId) {
            nextTierId += 1;
        }
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function deactivateTier(
        uint256 tier
    ) external onlyOwner {
        if (!_tierInfoByTier[tier].isActive) revert InvalidTier();

        emit DeactivateTier(tier);

        _tierInfoByTier[tier].isActive = false;
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function sweepToken(address token, address to) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        emit SweepToken(token, to, balance);
        IERC20(token).safeTransfer(to, balance);
    }
}
