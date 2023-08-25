// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

interface IStorageRegistry {
    /*//////////////////////////////////////////////////////////////
                        STORAGE RENTAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Rent storage for a given fid for a year. The caller must provide at least
     *         price(units) wei of payment. Any excess payment will be refunded to the caller. Hubs
     *         will issue storage for 365 days + 30 day grace period after which it expires.
     *
     *         RentedUnits is never decremented on the contract even as the assigned storage expires
     *         on the hubs. This is done to keep the contract simple since we expect to launch a new
     *         storage contract within the year and deprecate this one. Even if that does not occur,
     *         the existing maxUnits parameter can be tweaked to account for expired units.
     *
     * @param fid   The fid that will receive the storage units.
     * @param units Number of storage units to rent.
     */
    function rent(uint256 fid, uint256 units) external payable returns (uint256 overpayment);

    /**
     * @notice Rent storage for multiple fids for a year. The caller must provide at least
     *         price(units) wei of payment where units is the sum of storage units requested across
     *         the fids. See comments on rent() for additional details.
     *
     * @param fids  An array of fids.
     * @param units An array of storage unit quantities. Must be the same length as the fids array.
     */
    function batchRent(uint256[] calldata fids, uint256[] calldata units) external payable;

    /*//////////////////////////////////////////////////////////////
                              PRICE VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the cost in wei to rent one storage unit.
     *
     * @return uint256 cost in wei.
     */
    function unitPrice() external view returns (uint256);

    /**
     * @notice Calculate the cost in wei to rent the given number of storage units.
     *
     * @param units Number of storage units.
     * @return uint256 cost in wei.
     */
    function price(uint256 units) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Credit a single fid with free storage units. Only callable by operator.
     *
     * @param fid   The fid that will receive the credit.
     * @param units Number of storage units to credit.
     */
    function credit(uint256 fid, uint256 units) external;

    /**
     * @notice Credit multiple fids with free storage units. Only callable by operator.
     *
     * @param fids  An array of fids.
     * @param units Number of storage units per fid.
     */
    function batchCredit(uint256[] calldata fids, uint256 units) external;

    /**
     * @notice Credit a continuous sequence of fids with free storage units. Only callable by operator.
     *
     * @param start Lowest fid in sequence (inclusive).
     * @param end   Highest fid in sequence (inclusive).
     * @param units Number of storage units per fid.
     */
    function continuousCredit(uint256 start, uint256 end, uint256 units) external;

    /**
     * @notice Force refresh the cached Chainlink ETH/USD price. Callable by owner and treasurer.
     */
    function refreshPrice() external;

    /**
     * @notice Change the price feed addresss. Callable by owner.
     *
     * @param feed The new price feed.
     */
    function setPriceFeed(AggregatorV3Interface feed) external;

    /**
     * @notice Change the uptime feed addresss. Callable by owner.
     *
     * @param feed The new uptime feed.
     */
    function setUptimeFeed(AggregatorV3Interface feed) external;

    /**
     * @notice Change the USD price per storage unit. Callable by owner.
     *
     * @param usdPrice The new unit price in USD. Fixed point value with 8 decimals.
     */
    function setPrice(uint256 usdPrice) external;

    /**
     * @notice Set the fixed ETH/USD price, disabling the price feed if the value is
     *         nonzero. This is an emergency fallback in case of a price feed failure.
     *         Only callable by owner.
     *
     * @param fixedPrice The new fixed ETH/USD price. Fixed point value with 8 decimals.
     *                   Setting this value back to zero from a nonzero value will
     *                   re-enable the price feed.
     */
    function setFixedEthUsdPrice(uint256 fixedPrice) external;

    /**
     * @notice Change the maximum supply of storage units. Only callable by owner.
     *
     * @param max The new maximum supply of storage units.
     */
    function setMaxUnits(uint256 max) external;

    /**
     * @notice Change the deprecationTimestamp. Only callable by owner.
     *
     * @param timestamp The new deprecationTimestamp. Must be at least equal to block.timestamp.
     */
    function setDeprecationTimestamp(uint256 timestamp) external;

    /**
     * @notice Change the priceFeedCacheDuration. Only callable by owner.
     *
     * @param duration The new priceFeedCacheDuration.
     */
    function setCacheDuration(uint256 duration) external;

    /**
     * @notice Change the priceFeedMaxAge. Only callable by owner.
     *
     * @param age The new priceFeedMaxAge.
     */
    function setMaxAge(uint256 age) external;

    /**
     * @notice Change the priceFeedMinAnswer. Only callable by owner.
     *
     * @param minPrice The new priceFeedMinAnswer. Must be less than current priceFeedMaxAnswer.
     */
    function setMinAnswer(uint256 minPrice) external;

    /**
     * @notice Change the priceFeedMaxAnswer. Only callable by owner.
     *
     * @param maxPrice The new priceFeedMaxAnswer. Must be greater than current priceFeedMinAnswer.
     */
    function setMaxAnswer(uint256 maxPrice) external;

    /**
     * @notice Change the uptimeFeedGracePeriod. Only callable by owner.
     *
     * @param period The new uptimeFeedGracePeriod.
     */
    function setGracePeriod(uint256 period) external;

    /**
     * @notice Change the vault address that can receive funds from this contract.
     *         Only callable by owner.
     *
     * @param vaultAddr The new vault address.
     */
    function setVault(address vaultAddr) external;

    /**
     * @notice Withdraw a specified amount of ether from the contract balance to the vault.
     *         Only callable by treasurer.
     *
     * @param amount The amount of ether to withdraw.
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Pause, disabling rentals and credits.
     *         Only callable by owner.
     */
    function pause() external;

    /**
     * @notice Unpause, enabling rentals and credits.
     *         Only callable by owner.
     */
    function unpause() external;
}
