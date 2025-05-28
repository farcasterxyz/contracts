// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AccessControlEnumerable} from "openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITierRegistry} from "./interfaces/ITierRegistry.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

/**
 * @title Farcaster StorageRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract TierRegistry is ITierRegistry, AccessControlEnumerable, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller attempts to rent zero units.
    error InvalidAmount();

    error InvalidTier();

    error InvalidPrice();

    error InvalidBatchInput();

    error InvalidAddress();

    /// @dev Revert if the caller is not an owner.
    error NotOwner();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // TODO(aditi): Maybe rename without Purchase in name
    event PurchasedTier(uint256 indexed fid, uint256 indexed tier, uint256 forDays);

    event RemoveTier(uint256 tier);

    event SetTier(
        uint256 tier, uint256 minDays, uint256 maxDays, address vault, address paymentToken, uint256 tokenPricePerDay
    );

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    string public constant VERSION = "2025.05.21";
    // TODO(aditi): Update the date

    bytes32 internal constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    struct TierInfo {
        uint256 minDays;
        uint256 maxDays;
        address vault;
        IERC20 paymentToken;
        // Keep tier a number not enum so we don't need to ugrade contract to add a new one.
        uint256 tokenPricePerDay;
        bool isActive;
    }

    mapping(uint256 => TierInfo) public tierInfoByTier;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the price feed, uptime feed, and initial parameters.
     *
     * @param _initialOwner                  Initial owner address.
     */
    constructor(
        address _initialOwner
    ) {
        _grantRole(OWNER_ROLE, _initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (!hasRole(OWNER_ROLE, msg.sender)) revert NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE RENTAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    function purchaseTier(uint256 fid, uint256 tier, uint256 forDays, address payer) external whenNotPaused {
        TierInfo storage tierInfo = tierInfoByTier[tier];
        if (forDays == 0) revert InvalidAmount();
        if (!tierInfo.isActive) revert InvalidTier();
        if (forDays < tierInfo.minDays) revert InvalidAmount();
        if (forDays > tierInfo.maxDays) revert InvalidAmount();

        uint256 cost = tierInfo.tokenPricePerDay * forDays;

        emit PurchasedTier(fid, tier, forDays);

        tierInfo.paymentToken.safeTransferFrom(payer, tierInfo.vault, cost);
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function batchPurchaseTier(
        uint256 tier,
        uint256[] calldata fids,
        uint256[] calldata forDays,
        address payer
    ) external whenNotPaused {
        if (fids.length == 0) revert InvalidBatchInput();
        if (fids.length != forDays.length) revert InvalidBatchInput();

        TierInfo storage tierInfo = tierInfoByTier[tier];
        if (!tierInfo.isActive) revert InvalidTier();

        uint256 totalCost;
        for (uint256 i; i < fids.length; ++i) {
            uint256 numDays = forDays[i];
            if (numDays == 0) revert InvalidAmount();
            if (numDays < tierInfo.minDays) revert InvalidAmount();
            if (numDays > tierInfo.maxDays) revert InvalidAmount();
            totalCost += tierInfo.tokenPricePerDay * numDays;
        }

        for (uint256 i; i < fids.length; ++i) {
            emit PurchasedTier(fids[i], tier, forDays[i]);
        }

        tierInfo.paymentToken.safeTransferFrom(payer, tierInfo.vault, totalCost);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    function setTier(
        uint256 tier,
        address paymentToken,
        uint256 minDays,
        uint256 maxDays,
        uint256 tokenPricePerDay,
        address vault
    ) external onlyOwner {
        if (paymentToken == address(0)) revert InvalidAddress();
        if (minDays == 0) revert InvalidAddress();
        if (maxDays == 0) revert InvalidAddress();
        if (tokenPricePerDay == 0) revert InvalidAmount();
        if (vault == address(0)) revert InvalidAddress();

        emit SetTier(tier, minDays, maxDays, vault, paymentToken, tokenPricePerDay);

        tierInfoByTier[tier] = TierInfo({
            minDays: minDays,
            maxDays: maxDays,
            paymentToken: IERC20(paymentToken),
            tokenPricePerDay: tokenPricePerDay,
            vault: vault,
            isActive: true
        });
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function removeTier(
        uint256 tier
    ) external onlyOwner {
        if (!tierInfoByTier[tier].isActive) revert InvalidTier();

        emit RemoveTier(tier);

        tierInfoByTier[tier].isActive = false;
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
