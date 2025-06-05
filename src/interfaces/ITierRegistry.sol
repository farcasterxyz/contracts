// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IMigration} from "./abstract/IMigration.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ITierRegistry
 * @notice Interface for the TierRegistry contract that manages tier purchases for Farcaster IDs
 */
interface ITierRegistry is IMigration {
    /**
     * @notice Information about a user tier
     * @param minDays Minimum number of days that can be purchased for this tier
     * @param maxDays Maximum number of days that can be purchased for this tier
     * @param vault Address where payments for this tier are sent
     * @param paymentToken ERC20 token used for payments for this tier
     * @param tokenPricePerDay Price per day in the payment token for this tier
     * @param isActive Whether this tier is currently active and can be purchased
     */
    struct TierInfo {
        uint256 minDays;
        uint256 maxDays;
        address vault;
        IERC20 paymentToken;
        uint256 tokenPricePerDay;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller attempts to set a tier with price 0.
    error InvalidPrice();

    /// @dev Revert if the caller attempts to purchase a tier for no time.
    error InvalidDuration();

    /// @dev Revert if the caller specifies an inactive or nonexistent tier.
    error InvalidTier();

    /// @dev Revert if the caller attempts a batch rent with mismatched input array lengths or an empty array.
    error InvalidBatchInput();

    /// @dev Revert if the caller attempts to set a tier with a token address of 0
    error InvalidTokenAddress();

    /// @dev Revert if the caller attempts to set a tier with a vault address of 0
    error InvalidVaultAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a tier is purchased for a Farcaster ID
     * @param fid The Farcaster ID that the tier was purchased for
     * @param tier The tier ID that was purchased
     * @param forDays The number of days of subscription purchased
     * @param payer The address that paid
     */
    event PurchasedTier(uint256 indexed fid, uint256 indexed tier, uint256 forDays, address indexed payer);

    /**
     * @notice Emitted when a tier is deactivated
     * @param tier The tier ID that was deactivated
     */
    event DeactivateTier(uint256 indexed tier);

    /**
     * @notice Emitted when a tier is created or updated
     * @param tier The tier ID that was set
     * @param minDays Minimum number of days that can be purchased
     * @param maxDays Maximum number of days that can be purchased
     * @param vault Address where payments are sent
     * @param paymentToken ERC20 token used for payments
     * @param tokenPricePerDay Price per day in the payment token
     */
    event SetTier(
        uint256 indexed tier,
        uint256 minDays,
        uint256 maxDays,
        address vault,
        address paymentToken,
        uint256 tokenPricePerDay
    );

    /**
     * @notice Emitted when owner sweeps an ERC20 token balance
     * @param token ERC20 token address
     * @param to Address that receives the full balance
     * @param balance Token balance sent
     */
    event SweepToken(address indexed token, address to, uint256 balance);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the next tier ID that will be assigned
     * @return The next tier ID that will be used when creating a new tier
     */
    function nextTierId() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                               GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the total price for purchasing a tier for a specific number of days
     * @param tier The tier ID to calculate price for
     * @param forDays The number of days to calculate price for
     * @return The total price in the tier's payment token
     */
    function price(uint256 tier, uint256 forDays) external view returns (uint256);

    /**
     * @notice Get information about a specific tier
     * @param tier The tier ID to get information for
     * @return TierInfo struct containing all tier details
     */
    function tierInfo(
        uint256 tier
    ) external view returns (TierInfo memory);

    /*//////////////////////////////////////////////////////////////
                        TIER PURCHASING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase a tier for a specific Farcaster ID
     * @param fid The Farcaster ID to purchase the tier for
     * @param tier The tier ID to purchase
     * @param forDays The number of days to purchase the tier for
     */
    function purchaseTier(uint256 fid, uint256 tier, uint256 forDays) external;

    /**
     * @notice Purchase a tier for multiple Farcaster IDs in a single transaction
     * @param tier The tier ID to purchase for all FIDs
     * @param fids Array of Farcaster IDs to purchase for
     * @param forDays Array of days corresponding to each FID (must match fids array length)
     */
    function batchPurchaseTier(uint256 tier, uint256[] calldata fids, uint256[] calldata forDays) external;

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Credit a tier to multiple Farcaster IDs in a single transaction
     * @param tier The tier ID to credit for all FIDs
     * @param fids Array of Farcaster IDs to credit for
     * @param forDays Number of days to credit
     */
    function batchCreditTier(uint256 tier, uint256[] calldata fids, uint256 forDays) external;

    /**
     * @notice Update/create a user tier configuration
     *         Only callable by owner.
     * @param tier The tier ID to set
     * @param paymentToken The ERC20 token address to accept as payment
     * @param minDays Minimum number of days that can be purchased
     * @param maxDays Maximum number of days that can be purchased
     * @param tokenPricePerDay Price per day in the payment token
     * @param vault Address where payments will be sent
     */
    function setTier(
        uint256 tier,
        address paymentToken,
        uint256 minDays,
        uint256 maxDays,
        uint256 tokenPricePerDay,
        address vault
    ) external;

    /**
     * @notice Deactivate a tier, preventing new purchases
     *         Only callable by owner.
     * @param tier The tier ID to deactivate
     */
    function deactivateTier(
        uint256 tier
    ) external;

    /**
     * @notice Rescue an ERC20 token accidentally sent to this contract
     * @param token The token address
     * @param to Receiver address that will receive the full token balance
     */
    function sweepToken(address token, address to) external;
}
