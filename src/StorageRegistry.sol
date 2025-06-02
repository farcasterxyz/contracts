// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {AccessControlEnumerable} from "openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {IStorageRegistry} from "./interfaces/IStorageRegistry.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

/**
 * @title Farcaster StorageRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract StorageRegistry is IStorageRegistry, AccessControlEnumerable, Pausable {
    using FixedPointMathLib for uint256;
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller attempts to rent storage after the contract is deprecated.
    error ContractDeprecated();

    /// @dev Revert if the caller attempts to rent more storage than is available.
    error ExceedsCapacity();

    /// @dev Revert if the caller attempts to rent zero units.
    error InvalidAmount();

    /// @dev Revert if the caller attempts a batch rent with mismatched input array lengths or an empty array.
    error InvalidBatchInput();

    /// @dev Revert if the caller provides the wrong payment amount.
    error InvalidPayment();

    /// @dev Revert if the price feed returns a stale answer.
    error StaleAnswer();

    /// @dev Revert if any data feed round is incomplete and has not yet generated an answer.
    error IncompleteRound();

    /// @dev Revert if any data feed returns a timestamp in the future.
    error InvalidRoundTimestamp();

    /// @dev Revert if the price feed returns a value greater than the min/max bound.
    error PriceOutOfBounds();

    /// @dev Revert if the price feed returns a zero or negative price.
    error InvalidPrice();

    /// @dev Revert if the sequencer uptime feed detects that the L2 sequencer is unavailable.
    error SequencerDown();

    /// @dev Revert if the L2 sequencer restarted less than L2_DOWNTIME_GRACE_PERIOD seconds ago.
    error GracePeriodNotOver();

    /// @dev Revert if the deprecation timestamp parameter is in the past.
    error InvalidDeprecationTimestamp();

    /// @dev Revert if the priceFeedMinAnswer parameter is greater than or equal to priceFeedMaxAnswer.
    error InvalidMinAnswer();

    /// @dev Revert if the priceFeedMaxAnswer parameter is less than or equal to priceFeedMinAnswer.
    error InvalidMaxAnswer();

    /// @dev Revert if the fixedEthUsdPrice is outside the configured price bounds.
    error InvalidFixedPrice();

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

    /// @dev Revert if the caller attempts a continuous credit with an invalid range.
    error InvalidRangeInput();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when a caller pays rent for an fid's storage.
     *
     *      Hubs increment the units assigned to the fid for exactly 395 days (1 year + grace) from
     *      the event timestamp. Hubs track this for unregistered fids and will assign units when
     *      the fid is registered. Storage credited to fid 0 is a no-op.
     *
     * @param payer     Address of the account paying the storage rent.
     * @param fid       The fid that will receive the storage units.
     * @param units     The number of storage units being rented.
     */
    event Rent(address indexed payer, uint256 indexed fid, uint256 units);

    /**
     * @dev Emit an event when an owner changes the price feed address.
     *
     * @param oldFeed The previous price feed address.
     * @param newFeed The new price feed address.
     */
    event SetPriceFeed(address oldFeed, address newFeed);

    /**
     * @dev Emit an event when an owner changes the uptime feed address.
     *
     * @param oldFeed The previous uptime feed address.
     * @param newFeed The new uptime feed address.
     */
    event SetUptimeFeed(address oldFeed, address newFeed);

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
     *      Hub operators should be made aware of changes to storage requirements before they occur
     *      since it may cause Hubs to fail if they do not allocate sufficient storage.
     *
     * @param oldMax The previous maximum amount.
     * @param newMax The new maximum amount.
     */
    event SetMaxUnits(uint256 oldMax, uint256 newMax);

    /**
     * @dev Emit an event when an owner changes the deprecationTimestamp.
     *
     *      Hubs will stop listening to events after the deprecationTimestamp. This can be used
     *      when cutting over to a new contract. Hubs assume the following invariants:
     *
     *      1. SetDeprecationTimestamp() is only emitted once.
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
     * @dev Emit an event when an owner changes the priceFeedMinAnswer.
     *
     * @param oldPrice The previous priceFeedMinAnswer.
     * @param newPrice The new priceFeedMaxAnswer.
     */
    event SetMinAnswer(uint256 oldPrice, uint256 newPrice);

    /**
     * @dev Emit an event when an owner changes the priceFeedMaxAnswer.
     *
     * @param oldPrice The previous priceFeedMaxAnswer.
     * @param newPrice The new priceFeedMaxAnswer.
     */
    event SetMaxAnswer(uint256 oldPrice, uint256 newPrice);

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
     * @dev Emit an event when a treasurer withdraws any contract balance to the vault.
     *
     * @param to     Address of recipient.
     * @param amount The amount of ether withdrawn.
     */
    event Withdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IStorageRegistry
     */
    string public constant VERSION = "2023.08.23";

    bytes32 internal constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IStorageRegistry
     */
    AggregatorV3Interface public priceFeed;

    /**
     * @inheritdoc IStorageRegistry
     */
    AggregatorV3Interface public uptimeFeed;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public deprecationTimestamp;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public usdUnitPrice;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public fixedEthUsdPrice;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public maxUnits;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public priceFeedCacheDuration;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public priceFeedMaxAge;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public priceFeedMinAnswer;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public priceFeedMaxAnswer;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public uptimeFeedGracePeriod;

    /**
     * @inheritdoc IStorageRegistry
     */
    address public vault;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public rentedUnits;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public ethUsdPrice;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public prevEthUsdPrice;

    /**
     * @inheritdoc IStorageRegistry
     */
    uint256 public lastPriceFeedUpdateTime;

    /**
     * @inheritdoc IStorageRegistry
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
     * @param _initialUsdUnitPrice           Initial unit price in USD. Fixed point 8 decimal value.
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
        uint256 _initialUsdUnitPrice,
        uint256 _initialMaxUnits,
        address _initialVault,
        address _initialRoleAdmin,
        address _initialOwner,
        address _initialOperator,
        address _initialTreasurer
    ) {
        priceFeed = _priceFeed;
        emit SetPriceFeed(address(0), address(_priceFeed));

        uptimeFeed = _uptimeFeed;
        emit SetUptimeFeed(address(0), address(_uptimeFeed));

        deprecationTimestamp = block.timestamp + 365 days;
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

        priceFeedMinAnswer = 100e8; // 100 USD / ETH
        emit SetMinAnswer(0, 100e8);

        priceFeedMaxAnswer = 10_000e8; // 10_000 USD / ETH
        emit SetMaxAnswer(0, 10_000e8);

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
        if (block.timestamp >= deprecationTimestamp) {
            revert ContractDeprecated();
        }
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
     * @inheritdoc IStorageRegistry
     */
    function rent(
        uint256 fid,
        uint256 units
    ) external payable whenNotDeprecated whenNotPaused returns (uint256 overpayment) {
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
     * @inheritdoc IStorageRegistry
     */
    function batchRent(
        uint256[] calldata fids,
        uint256[] calldata units
    ) external payable whenNotDeprecated whenNotPaused {
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
     * @inheritdoc IStorageRegistry
     */
    function unitPrice() external view returns (uint256) {
        return price(1);
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function price(
        uint256 units
    ) public view returns (uint256) {
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
     * @dev Return the fixed price if present and the cached ethUsdPrice if it is not. If cached
     *      price is no longer valid, refresh the cache from the price feed but return the cached
     *      price for the rest of this block to avoid unexpected price changes.
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
         */

        // slither-disable-next-line incorrect-equality
        return (lastPriceFeedUpdateBlock == block.number) ? prevEthUsdPrice : ethUsdPrice;
    }

    /**
     * @dev Get the latest ETH/USD price from the price feed and update the cached price.
     */
    function _refreshPrice() internal {
        /**
         *  Get and validate the L2 sequencer status.
         *  We ignore the deprecated answeredInRound value.
         */

        // slither-disable-next-line unused-return
        (uint80 uptimeRoundId, int256 sequencerUp, uint256 uptimeStartedAt, uint256 uptimeUpdatedAt,) =
            uptimeFeed.latestRoundData();
        if (sequencerUp != 0) revert SequencerDown();
        if (uptimeRoundId == 0) revert IncompleteRound();
        if (uptimeUpdatedAt == 0) revert IncompleteRound();
        if (uptimeUpdatedAt > block.timestamp) revert InvalidRoundTimestamp();

        /* If the L2 sequencer recently restarted, ensure the grace period has elapsed. */
        uint256 timeSinceUp = block.timestamp - uptimeStartedAt;
        if (timeSinceUp < uptimeFeedGracePeriod) revert GracePeriodNotOver();

        /**
         *  Get and validate the Chainlink ETH/USD price. Validate that the answer is a positive
         *  value, the round is complete, and the answer is not stale by round.
         *
         *  Ignore the deprecated answeredInRound value.
         *
         *  Ignore the price feed startedAt value, which isn't used in validations, since the
         *  priceUpdatedAt timestamp is more meaningful.
         *
         *  Slither flags this as an unused return value error, but this is safe since
         *  we use priceUpdatedAt and are interested in the latest value.
         */

        // slither-disable-next-line unused-return
        (uint80 priceRoundId, int256 answer,, uint256 priceUpdatedAt,) = priceFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (priceRoundId == 0) revert IncompleteRound();
        if (priceUpdatedAt == 0) revert IncompleteRound();
        if (priceUpdatedAt > block.timestamp) revert InvalidRoundTimestamp();
        if (block.timestamp - priceUpdatedAt > priceFeedMaxAge) {
            revert StaleAnswer();
        }
        if (uint256(answer) < priceFeedMinAnswer || uint256(answer) > priceFeedMaxAnswer) revert PriceOutOfBounds();

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

    /**
     * @dev Calculate the cost in wei to rent storage units.
     */
    function _price(
        uint256 units
    ) internal returns (uint256) {
        return _price(units, usdUnitPrice, _ethUsdPrice());
    }

    /**
     * @dev Calculate the cost in wei to rent storage units.
     *
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
     * @inheritdoc IStorageRegistry
     */
    function credit(uint256 fid, uint256 units) external onlyOperator whenNotDeprecated whenNotPaused {
        if (units == 0) revert InvalidAmount();
        if (rentedUnits + units > maxUnits) revert ExceedsCapacity();

        rentedUnits += units;
        emit Rent(msg.sender, fid, units);
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function batchCredit(
        uint256[] calldata fids,
        uint256 units
    ) external onlyOperator whenNotDeprecated whenNotPaused {
        if (units == 0) revert InvalidAmount();
        uint256 totalUnits = fids.length * units;
        if (rentedUnits + totalUnits > maxUnits) revert ExceedsCapacity();
        rentedUnits += totalUnits;
        for (uint256 i; i < fids.length; ++i) {
            emit Rent(msg.sender, fids[i], units);
        }
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function continuousCredit(
        uint256 start,
        uint256 end,
        uint256 units
    ) external onlyOperator whenNotDeprecated whenNotPaused {
        if (units == 0) revert InvalidAmount();
        if (start >= end) revert InvalidRangeInput();

        uint256 len = end - start + 1;
        uint256 totalUnits = len * units;
        if (rentedUnits + totalUnits > maxUnits) revert ExceedsCapacity();
        rentedUnits += totalUnits;
        for (uint256 i; i < len; ++i) {
            emit Rent(msg.sender, start + i, units);
        }
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function refreshPrice() external {
        if (!hasRole(OWNER_ROLE, msg.sender) && !hasRole(TREASURER_ROLE, msg.sender)) revert Unauthorized();
        _refreshPrice();
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setPriceFeed(
        AggregatorV3Interface feed
    ) external onlyOwner {
        emit SetPriceFeed(address(priceFeed), address(feed));
        priceFeed = feed;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setUptimeFeed(
        AggregatorV3Interface feed
    ) external onlyOwner {
        emit SetUptimeFeed(address(uptimeFeed), address(feed));
        uptimeFeed = feed;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setPrice(
        uint256 usdPrice
    ) external onlyOwner {
        emit SetPrice(usdUnitPrice, usdPrice);
        usdUnitPrice = usdPrice;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setFixedEthUsdPrice(
        uint256 fixedPrice
    ) external onlyOwner {
        if (fixedPrice != 0) {
            if (fixedPrice < priceFeedMinAnswer || fixedPrice > priceFeedMaxAnswer) revert InvalidFixedPrice();
        }
        emit SetFixedEthUsdPrice(fixedEthUsdPrice, fixedPrice);
        fixedEthUsdPrice = fixedPrice;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setMaxUnits(
        uint256 max
    ) external onlyOwner {
        emit SetMaxUnits(maxUnits, max);
        maxUnits = max;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setDeprecationTimestamp(
        uint256 timestamp
    ) external onlyOwner {
        if (timestamp < block.timestamp) revert InvalidDeprecationTimestamp();
        emit SetDeprecationTimestamp(deprecationTimestamp, timestamp);
        deprecationTimestamp = timestamp;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setCacheDuration(
        uint256 duration
    ) external onlyOwner {
        emit SetCacheDuration(priceFeedCacheDuration, duration);
        priceFeedCacheDuration = duration;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setMaxAge(
        uint256 age
    ) external onlyOwner {
        emit SetMaxAge(priceFeedMaxAge, age);
        priceFeedMaxAge = age;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setMinAnswer(
        uint256 minPrice
    ) external onlyOwner {
        if (minPrice >= priceFeedMaxAnswer) revert InvalidMinAnswer();
        emit SetMinAnswer(priceFeedMinAnswer, minPrice);
        priceFeedMinAnswer = minPrice;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setMaxAnswer(
        uint256 maxPrice
    ) external onlyOwner {
        if (maxPrice <= priceFeedMinAnswer) revert InvalidMaxAnswer();
        emit SetMaxAnswer(priceFeedMaxAnswer, maxPrice);
        priceFeedMaxAnswer = maxPrice;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setGracePeriod(
        uint256 period
    ) external onlyOwner {
        emit SetGracePeriod(uptimeFeedGracePeriod, period);
        uptimeFeedGracePeriod = period;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function setVault(
        address vaultAddr
    ) external onlyOwner {
        if (vaultAddr == address(0)) revert InvalidAddress();
        emit SetVault(vault, vaultAddr);
        vault = vaultAddr;
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function withdraw(
        uint256 amount
    ) external onlyTreasurer {
        emit Withdraw(vault, amount);
        vault.sendNative(amount);
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc IStorageRegistry
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
