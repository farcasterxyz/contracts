// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {AccessControlEnumerable} from "openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {TransferHelper} from "./lib/TransferHelper.sol";

/**
 * @title StorageRegistry
 *
 * @notice See ../docs/docs.md for an overview.
 */
contract StorageRegistry is AccessControlEnumerable {
    using FixedPointMathLib for uint256;
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller attempts to rent storage after deprecating this contract.
    error ContractDeprecated();

    /// @dev Revert if the caller attempts to rent more storage than is available.
    error ExceedsCapacity();

    /// @dev Revert if the caller attempts to rent zero units.
    error InvalidAmount();

    /// @dev Revert if the caller attempts a batch rent with mismatched input array lengths or an empty array.
    error InvalidBatchInput();

    /// @dev Revert if the caller provides the wrong payment amount.
    error InvalidPayment();

    /// @dev Revert if a data feed returns a stale answer.
    error StaleAnswer();

    /// @dev Revert if the data feed round is incomplete and has not yet generated an answer.
    error IncompleteRound();

    /// @dev Revert if the price feed returns a zero or negative price.
    error InvalidPrice();

    /// @dev Revert if the sequencer uptime feed detects that the L2 sequencer is unavailable.
    error SequencerDown();

    /// @dev Revert if the L2 sequencer restarted less than L2_DOWNTIME_GRACE_PERIOD seconds ago.
    error GracePeriodNotOver();

    /// @dev Revert if the deprecation timestamp parameter is in the past.
    error InvalidDeprecationTimestamp();

    /// @dev Revert if the caller is not an owner.
    error NotOwner();

    /// @dev Revert if the caller is not an operator.
    error NotOperator();

    /// @dev Revert if the caller is not a treasurer.
    error NotTreasurer();

    /// @dev Revert if the caller does not have an authorized role.
    error Unauthorized();

    /// @dev Revert if transferred to the zero address.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when caller pays rent for an fid's storage.
     *
     *      Hubs listen for this event and increment the units assigned to the fid by 1 for exactly
     *      395 days from the timestamp of this event (1 year + 30 day grace period). Hubs respect
     *      this even if the fid is not yet issued.
     *
     * @param payer     Address of the account paying the storage rent.
     * @param fid       The fid that will receive the storage allocation.
     * @param units     The number of storage units being rented.
     */
    event Rent(address indexed payer, uint256 indexed fid, uint256 units);

    /**
     * @dev Emit an event when an owner changes the price of storage units.
     *
     * @param oldPrice The previous unit price in USD. Fixed point value with 8 decimals.
     * @param newPrice The new unit price in USD. Fixed point value with 8 decimals.
     */
    event SetPrice(uint256 oldPrice, uint256 newPrice);

    /**
     * @dev Emit an event when an owner changes the fixed ETH/USD price.
     *      Setting this value to zero means the fixed price is disabled.
     *
     * @param oldPrice The previous ETH price in USD. Fixed point value with 8 decimals.
     * @param newPrice The new ETH price in USD. Fixed point value with 8 decimals.
     */
    event SetFixedEthUsdPrice(uint256 oldPrice, uint256 newPrice);

    /**
     * @dev Emit an event when an owner changes the maximum supply of storage units.
     *
     *      Hubs do not actively listen for this event, though the owner of the contract is
     *      responsible for ensuring that Hub operators are aware of the new storage requirements,
     *      since that may cause Hubs to fail if they do not allocate sufficient storage.
     *
     * @param oldMax The previous maximum amount.
     * @param newMax The new maximum amount.
     */
    event SetMaxUnits(uint256 oldMax, uint256 newMax);

    /**
     * @dev Emit an event when an owner changes the deprecationTimestamp.
     *
     * @param oldTimestamp The previous deprecationTimestamp.
     * @param newTimestamp The new deprecationTimestamp.
     */
    event SetDeprecationTimestamp(uint256 oldTimestamp, uint256 newTimestamp);

    /**
     * @dev Emit an event when an owner changes the priceFeedCacheDuration.
     *
     * @param oldDuration The previous priceFeedCacheDuration.
     * @param newDuration The new priceFeedCacheDuration.
     */
    event SetCacheDuration(uint256 oldDuration, uint256 newDuration);

    /**
     * @dev Emit an event when an owner changes the priceFeedMaxAge.
     *
     * @param oldAge The previous priceFeedMaxAge.
     * @param newAge The new priceFeedMaxAge.
     */
    event SetMaxAge(uint256 oldAge, uint256 newAge);

    /**
     * @dev Emit an event when an owner changes the uptimeFeedGracePeriod.
     *
     * @param oldPeriod The previous uptimeFeedGracePeriod.
     * @param newPeriod The new uptimeFeedGracePeriod.
     */
    event SetGracePeriod(uint256 oldPeriod, uint256 newPeriod);

    /**
     * @dev Emit an event when an owner changes the vault.
     *
     * @param oldVault The previous vault.
     * @param newVault The new vault.
     */
    event SetVault(address oldVault, address newVault);

    /**
     * @dev Emit an event when a treasurer makes a withdrawal from the contract balance.
     *
     * @param to     Address of recipient.
     * @param amount The amount of ether withdrawn.
     */
    event Withdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Contract version specified in the Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.07.12";

    bytes32 internal constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Chainlink ETH/USD price feed.
     */
    AggregatorV3Interface public immutable priceFeed;

    /**
     * @dev Chainlink L2 sequencer uptime feed.
     */
    AggregatorV3Interface public immutable uptimeFeed;

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Block timestamp at which this contract will no longer accept storage rent payments. Changeable by owner.
     */
    uint256 public deprecationTimestamp;

    /**
     * @dev Price per storage unit in USD. Fixed point value with 8 decimals, e.g. 5e8 = $5 USD. Changeable by owner.
     */
    uint256 public usdUnitPrice;

    /**
     * @dev A fixed ETH/USD price to be used in the event of a price feed failure. If this value
     *      is nonzero, we disable external calls to the price feed and use this price. Changeable by owner.
     */
    uint256 public fixedEthUsdPrice;

    /**
     * @dev Total capacity of storage units. Changeable by owner.
     */
    uint256 public maxUnits;

    /**
     * @dev Duration to cache ethUsdPrice before updating from the price feed. Changeable by owner.
     */
    uint256 public priceFeedCacheDuration;

    /**
     * @dev Max age of a price feed answer before it is considered stale. Changeable by owner.
     */
    uint256 public priceFeedMaxAge;

    /**
     * @dev Period in seconds to wait after the L2 sequencer restarts before resuming rentals.
     *      See: https://docs.chain.link/data-feeds/l2-sequencer-feeds. Changeable by owner.
     */
    uint256 public uptimeFeedGracePeriod;

    /**
     * @dev Address to which the treasurer role can withdraw funds. Changeable by owner.
     */
    address public vault;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Total number of storage units that have been rented.
     */
    uint256 public rentedUnits;

    /**
     * @dev Cached Chainlink ETH/USD price.
     */
    uint256 public ethUsdPrice;

    /**
     * @dev Previous Chainlink ETH/USD price.
     */
    uint256 public prevEthUsdPrice;

    /**
     * @dev Timestamp of the last update to ethUsdPrice.
     */
    uint256 public lastPriceFeedUpdateTime;

    /**
     * @dev Block number of the last update to ethUsdPrice.
     */
    uint256 public lastPriceFeedUpdateBlock;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the price feed, uptime feed, and initial parameters.
     *
     * @param _priceFeed                     Chainlink ETH/USD price feed.
     * @param _uptimeFeed                    Chainlink L2 sequencer uptime feed.
     * @param _initialDeprecationPeriod      Initial deprecation period in seconds.
     * @param _initialUsdUnitPrice           Initial unit price in USD. Fixed point value with 8 decimals.
     * @param _initialMaxUnits               Initial maximum capacity in storage units.
     * @param _initialVault                  Initial vault address.
     * @param _initialRoleAdmin              Initial role admin address.
     * @param _initialOwner                  Initial owner address.
     * @param _initialOperator               Initial operator address.
     * @param _initialTreasurer              Initial treasurer address.
     */
    constructor(
        AggregatorV3Interface _priceFeed,
        AggregatorV3Interface _uptimeFeed,
        uint256 _initialDeprecationPeriod,
        uint256 _initialUsdUnitPrice,
        uint256 _initialMaxUnits,
        address _initialVault,
        address _initialRoleAdmin,
        address _initialOwner,
        address _initialOperator,
        address _initialTreasurer
    ) {
        priceFeed = _priceFeed;
        uptimeFeed = _uptimeFeed;

        deprecationTimestamp = block.timestamp + _initialDeprecationPeriod;
        emit SetDeprecationTimestamp(0, deprecationTimestamp);

        usdUnitPrice = _initialUsdUnitPrice;
        emit SetPrice(0, _initialUsdUnitPrice);

        maxUnits = _initialMaxUnits;
        emit SetMaxUnits(0, _initialMaxUnits);

        priceFeedCacheDuration = 1 days;
        emit SetCacheDuration(0, 1 days);

        priceFeedMaxAge = 2 hours;
        emit SetMaxAge(0, 2 hours);

        uptimeFeedGracePeriod = 1 hours;
        emit SetGracePeriod(0, 1 hours);

        vault = _initialVault;
        emit SetVault(address(0), _initialVault);

        _grantRole(DEFAULT_ADMIN_ROLE, _initialRoleAdmin);
        _grantRole(OWNER_ROLE, _initialOwner);
        _grantRole(OPERATOR_ROLE, _initialOperator);
        _grantRole(TREASURER_ROLE, _initialTreasurer);

        _refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier whenNotDeprecated() {
        if (block.timestamp >= deprecationTimestamp) revert ContractDeprecated();
        _;
    }

    modifier onlyOwner() {
        if (!hasRole(OWNER_ROLE, msg.sender)) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _;
    }

    modifier onlyTreasurer() {
        if (!hasRole(TREASURER_ROLE, msg.sender)) revert NotTreasurer();
        _;
    }

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
     * @param fid   The fid that will receive the storage allocation.
     * @param units Number of storage units to rent.
     */
    function rent(uint256 fid, uint256 units) external payable whenNotDeprecated returns (uint256 overpayment) {
        // Checks
        if (units == 0) revert InvalidAmount();
        if (rentedUnits + units > maxUnits) revert ExceedsCapacity();
        uint256 totalPrice = _price(units);
        if (msg.value < totalPrice) revert InvalidPayment();

        // Effects
        rentedUnits += units;
        emit Rent(msg.sender, fid, units);

        // Interactions
        // Safety: overpayment is guaranteed to be >=0 because of checks
        overpayment = msg.value - totalPrice;
        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /**
     * @notice Rent storage for multiple fids. The caller must provide an exact payment amount equal to
     *         the sum of the prices for each fid's storage allocation.
     *
     * @param fids  An array of fids.
     * @param units An array of storage unit quantities. Must be the same length as the fids array.
     */
    function batchRent(uint256[] calldata fids, uint256[] calldata units) external payable whenNotDeprecated {
        // Pre-checks
        if (fids.length == 0 || units.length == 0) revert InvalidBatchInput();
        if (fids.length != units.length) revert InvalidBatchInput();

        // Effects
        uint256 _usdPrice = usdUnitPrice;
        uint256 _ethPrice = _ethUsdPrice();

        uint256 totalQty;
        for (uint256 i; i < fids.length; ++i) {
            uint256 qty = units[i];
            if (qty == 0) continue;
            totalQty += qty;
            emit Rent(msg.sender, fids[i], qty);
        }
        uint256 totalPrice = _price(totalQty, _usdPrice, _ethPrice);

        // Post-checks
        if (msg.value < totalPrice) revert InvalidPayment();
        if (rentedUnits + totalQty > maxUnits) revert ExceedsCapacity();

        // Effects
        rentedUnits += totalQty;

        // Interactions
        if (msg.value > totalPrice) {
            msg.sender.sendNative(msg.value - totalPrice);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cost in wei to rent one storage unit.
     * @return uint256 cost in wei.
     */
    function unitPrice() external view returns (uint256) {
        return price(1);
    }

    /**
     * @notice Calculate the cost in wei to rent the given number of storage units.
     *
     * @param units Number of storage units.
     * @return uint256 cost in wei.
     */
    function price(uint256 units) public view returns (uint256) {
        uint256 ethPrice;
        if (fixedEthUsdPrice != 0) {
            ethPrice = fixedEthUsdPrice;

            /**
             *  Slither flags the following line as a dangerous strict equality, but we want to
             *  make an exact comparison here and are not using this value in the context
             *  this detector rule describes.
             */

            // slither-disable-next-line incorrect-equality
        } else if (lastPriceFeedUpdateBlock == block.number) {
            ethPrice = prevEthUsdPrice;
        } else {
            ethPrice = ethUsdPrice;
        }
        return _price(units, usdUnitPrice, ethPrice);
    }

    /**
     * @dev Return the cached ethUsdPrice if it's still valid, otherwise get the
     *      latest ETH/USD price from the price feed and update the cache.
     */
    function _ethUsdPrice() internal returns (uint256) {
        /**
         *  If a fixed ETH/USD price is set, use it. This disables external calls
         *  to the price feed in case of emergency.
         */
        if (fixedEthUsdPrice != 0) return fixedEthUsdPrice;

        /**
         *  If cache duration has expired, get the latest price from the price feed.
         *  This updates prevEthUsdPrice, ethUsdPrice, lastPriceFeedUpdateTime, and
         *  lastPriceFeedUpdateBlock.
         */
        if (block.timestamp - lastPriceFeedUpdateTime > priceFeedCacheDuration) {
            _refreshPrice();
        }

        /**
         *  We want price changes to take effect in the first block after the price
         *  refresh, rather than immediately, to keep the price from changing intra
         *  block. If we update the price in this block, use the previous price
         *  until the next block. Otherwise, use the latest price.
         *
         *  Slither flags this line as a dangerous strict equality, but we want to
         *  make an exact comparison here and are not using this value in the context
         *  this detector rule describes.
         *
         */

        // slither-disable-next-line incorrect-equality
        return (lastPriceFeedUpdateBlock == block.number) ? prevEthUsdPrice : ethUsdPrice;
    }

    /**
     * @dev Get the latest ETH/USD price from the price feed and update the cached price.
     */
    function _refreshPrice() internal {
        /* Get and validate the L2 sequencer status. */
        (
            uint80 uptimeRoundId,
            int256 sequencerUp,
            uint256 uptimeStartedAt,
            uint256 uptimeUpdatedAt,
            uint80 uptimeAnsweredInRound
        ) = uptimeFeed.latestRoundData();
        if (sequencerUp != 0) revert SequencerDown();
        if (uptimeUpdatedAt == 0) revert IncompleteRound();
        if (uptimeAnsweredInRound < uptimeRoundId) revert StaleAnswer();

        /* If the L2 sequencer recently restarted, ensure the grace period has elapsed. */
        uint256 timeSinceUp = block.timestamp - uptimeStartedAt;
        if (timeSinceUp < uptimeFeedGracePeriod) revert GracePeriodNotOver();

        /**
         *  Get and validate the Chainlink ETH/USD price. We validate that the answer is
         *  a positive value, the round is complete, and the answer is not stale by round.
         *
         *  We ignore the price feed startedAt value, which we don't use in validations,
         *  since the priceUpdatedAt timestamp is more meaningful.
         *
         *  Slither flags this as an unused return value error, but this is safe since
         *  we use priceUpdatedAt and are interested in the latest value.
         */

        // slither-disable-next-line unused-return
        (uint80 priceRoundId, int256 answer,, uint256 priceUpdatedAt, uint80 priceAnsweredInRound) =
            priceFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (priceUpdatedAt == 0) revert IncompleteRound();
        if (priceAnsweredInRound < priceRoundId) revert StaleAnswer();
        if (block.timestamp - priceUpdatedAt > priceFeedMaxAge) revert StaleAnswer();

        /* Set the last update timestamp and block. */
        lastPriceFeedUpdateTime = block.timestamp;
        lastPriceFeedUpdateBlock = block.number;

        if (prevEthUsdPrice == 0 && ethUsdPrice == 0) {
            /* If this is the very first price update, set previous equal to latest. */
            prevEthUsdPrice = ethUsdPrice = uint256(answer);
        } else {
            prevEthUsdPrice = ethUsdPrice;
            ethUsdPrice = uint256(answer);
        }
    }

    function _price(uint256 units) internal returns (uint256) {
        return _price(units, usdUnitPrice, _ethUsdPrice());
    }

    /**
     * @param units      Number of storage units. Integer, no decimals.
     * @param usdPerUnit Unit price in USD. Fixed point with 8 decimals.
     * @param usdPerEth  ETH/USD price. Fixed point with 8 decimals.
     *
     * @return uint256 price in wei, i.e. 18 decimals.
     */
    function _price(uint256 units, uint256 usdPerUnit, uint256 usdPerEth) internal pure returns (uint256) {
        return (units * usdPerUnit).divWadUp(usdPerEth);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Credit a single fid with free storage units. Only callable by operator.
     *
     * @param fid   The fid that will receive the credit.
     * @param units Number of storage units to credit.
     */
    function credit(uint256 fid, uint256 units) external onlyOperator whenNotDeprecated {
        if (units == 0) revert InvalidAmount();
        if (rentedUnits + units > maxUnits) revert ExceedsCapacity();

        rentedUnits += units;
        emit Rent(msg.sender, fid, units);
    }

    /**
     * @notice Credit multiple fids with free storage units. Only callable by operator.
     *
     * @param fids  An array of fids.
     * @param units Number of storage units per fid.
     */
    function batchCredit(uint256[] calldata fids, uint256 units) external onlyOperator whenNotDeprecated {
        if (units == 0) revert InvalidAmount();
        uint256 totalUnits = fids.length * units;
        if (rentedUnits + totalUnits > maxUnits) revert ExceedsCapacity();
        rentedUnits += totalUnits;
        for (uint256 i; i < fids.length; ++i) {
            emit Rent(msg.sender, fids[i], units);
        }
    }

    /**
     * @notice Credit a continuous sequence of fids with free storage units. Only callable by operator.
     *
     * @param start Lowest fid in sequence (inclusive).
     * @param end   Highest fid in sequence (inclusive).
     * @param units Number of storage units per fid.
     */
    function continuousCredit(uint256 start, uint256 end, uint256 units) external onlyOperator whenNotDeprecated {
        if (units == 0) revert InvalidAmount();
        uint256 len = end - start;
        uint256 totalUnits = len * units;
        if (rentedUnits + totalUnits > maxUnits) revert ExceedsCapacity();
        rentedUnits += totalUnits;
        for (uint256 i; i < len; ++i) {
            emit Rent(msg.sender, start + i, units);
        }
    }

    /**
     * @notice Force refresh the cached Chainlink ETH/USD price. Callable by owner and treasurer.
     */
    function refreshPrice() external {
        if (!hasRole(OWNER_ROLE, msg.sender) && !hasRole(TREASURER_ROLE, msg.sender)) revert Unauthorized();
        _refreshPrice();
    }

    /**
     * @notice Change the USD price per storage unit. Callable by owner and treasurer.
     *
     * @param usdPrice The new unit price in USD. Fixed point value with 8 decimals.
     */
    function setPrice(uint256 usdPrice) external {
        if (!hasRole(OWNER_ROLE, msg.sender) && !hasRole(TREASURER_ROLE, msg.sender)) revert Unauthorized();
        emit SetPrice(usdUnitPrice, usdPrice);
        usdUnitPrice = usdPrice;
    }

    /**
     * @notice Set the fixed ETH/USD price, disabling the price feed if the value is
     *         nonzero. This is an emergency fallback in case of a price feed failure.
     *         Only callable by owner.
     *
     * @param fixedPrice The new fixed ETH/USD price. Fixed point value with 8 decimals.
     *                   Setting this value back to zero from a nonzero value will
     *                   re-enable the price feed.
     */
    function setFixedEthUsdPrice(uint256 fixedPrice) external onlyOwner {
        emit SetFixedEthUsdPrice(fixedEthUsdPrice, fixedPrice);
        fixedEthUsdPrice = fixedPrice;
    }

    /**
     * @notice Change the maximum supply of storage units. Only callable by owner.
     *
     * @param max The new maximum supply of storage units.
     */
    function setMaxUnits(uint256 max) external onlyOwner {
        emit SetMaxUnits(maxUnits, max);
        maxUnits = max;
    }

    /**
     * @notice Change the deprecationTimestamp. Only callable by owner.
     *
     * @param timestamp The new deprecationTimestamp.
     */
    function setDeprecationTimestamp(uint256 timestamp) external onlyOwner {
        if (timestamp < block.timestamp) revert InvalidDeprecationTimestamp();
        emit SetDeprecationTimestamp(deprecationTimestamp, timestamp);
        deprecationTimestamp = timestamp;
    }

    /**
     * @notice Change the priceFeedCacheDuration. Only callable by owner.
     *
     * @param duration The new priceFeedCacheDuration.
     */
    function setCacheDuration(uint256 duration) external onlyOwner {
        emit SetCacheDuration(priceFeedCacheDuration, duration);
        priceFeedCacheDuration = duration;
    }

    /**
     * @notice Change the priceFeedMaxAge. Only callable by owner.
     *
     * @param age The new priceFeedMaxAge.
     */
    function setMaxAge(uint256 age) external onlyOwner {
        emit SetMaxAge(priceFeedMaxAge, age);
        priceFeedMaxAge = age;
    }

    /**
     * @notice Change the uptimeFeedGracePeriod. Only callable by owner.
     *
     * @param period The new uptimeFeedGracePeriod.
     */
    function setGracePeriod(uint256 period) external onlyOwner {
        emit SetGracePeriod(uptimeFeedGracePeriod, period);
        uptimeFeedGracePeriod = period;
    }

    /**
     * @notice Set the vault address that can receive funds from this contract.
     *         Only callable by owner.
     *
     * @param vaultAddr The new vault address.
     */
    function setVault(address vaultAddr) external onlyOwner {
        if (vaultAddr == address(0)) revert InvalidAddress();
        emit SetVault(vault, vaultAddr);
        vault = vaultAddr;
    }

    /**
     * @notice Withdraw a specified amount of ether from the contract balance to the vault.
     *         Only callable by treasurer.
     *
     * @param amount The amount of ether to withdraw.
     */
    function withdraw(uint256 amount) external onlyTreasurer {
        emit Withdraw(vault, amount);
        vault.sendNative(amount);
    }
}
