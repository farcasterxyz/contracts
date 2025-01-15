// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {AccessControlEnumerable} from "openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {IUSDPriceFeed} from "../interfaces/abstract/IUSDPriceFeed.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

abstract contract USDPriceFeed is IUSDPriceFeed, AccessControlEnumerable, Pausable {
    using FixedPointMathLib for uint256;
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

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
     * @dev Emit an event when an owner changes the unit price.
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

    string public constant VERSION = "2025.01.15";

    bytes32 internal constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    AggregatorV3Interface public priceFeed;

    AggregatorV3Interface public uptimeFeed;

    uint256 public usdUnitPrice;

    uint256 public fixedEthUsdPrice;

    uint256 public priceFeedCacheDuration;

    uint256 public priceFeedMaxAge;

    uint256 public priceFeedMinAnswer;

    uint256 public priceFeedMaxAnswer;

    uint256 public uptimeFeedGracePeriod;

    address public vault;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public ethUsdPrice;

    uint256 public prevEthUsdPrice;

    uint256 public lastPriceFeedUpdateTime;

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

        usdUnitPrice = _initialUsdUnitPrice;
        emit SetPrice(0, _initialUsdUnitPrice);

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
                              PRICE VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IUSDPriceFeed
     */
    function unitPrice() external view returns (uint256) {
        return price(1);
    }

    /**
     * @inheritdoc IUSDPriceFeed
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

    function refreshPrice() external {
        if (!hasRole(OWNER_ROLE, msg.sender) && !hasRole(TREASURER_ROLE, msg.sender)) revert Unauthorized();
        _refreshPrice();
    }

    function setPriceFeed(
        AggregatorV3Interface feed
    ) external onlyOwner {
        emit SetPriceFeed(address(priceFeed), address(feed));
        priceFeed = feed;
    }

    function setUptimeFeed(
        AggregatorV3Interface feed
    ) external onlyOwner {
        emit SetUptimeFeed(address(uptimeFeed), address(feed));
        uptimeFeed = feed;
    }

    function setPrice(
        uint256 usdPrice
    ) external onlyOwner {
        emit SetPrice(usdUnitPrice, usdPrice);
        usdUnitPrice = usdPrice;
    }

    function setFixedEthUsdPrice(
        uint256 fixedPrice
    ) external onlyOwner {
        if (fixedPrice != 0) {
            if (fixedPrice < priceFeedMinAnswer || fixedPrice > priceFeedMaxAnswer) revert InvalidFixedPrice();
        }
        emit SetFixedEthUsdPrice(fixedEthUsdPrice, fixedPrice);
        fixedEthUsdPrice = fixedPrice;
    }

    function setCacheDuration(
        uint256 duration
    ) external onlyOwner {
        emit SetCacheDuration(priceFeedCacheDuration, duration);
        priceFeedCacheDuration = duration;
    }

    function setMaxAge(
        uint256 age
    ) external onlyOwner {
        emit SetMaxAge(priceFeedMaxAge, age);
        priceFeedMaxAge = age;
    }

    function setMinAnswer(
        uint256 minPrice
    ) external onlyOwner {
        if (minPrice >= priceFeedMaxAnswer) revert InvalidMinAnswer();
        emit SetMinAnswer(priceFeedMinAnswer, minPrice);
        priceFeedMinAnswer = minPrice;
    }

    function setMaxAnswer(
        uint256 maxPrice
    ) external onlyOwner {
        if (maxPrice <= priceFeedMinAnswer) revert InvalidMaxAnswer();
        emit SetMaxAnswer(priceFeedMaxAnswer, maxPrice);
        priceFeedMaxAnswer = maxPrice;
    }

    function setGracePeriod(
        uint256 period
    ) external onlyOwner {
        emit SetGracePeriod(uptimeFeedGracePeriod, period);
        uptimeFeedGracePeriod = period;
    }

    function setVault(
        address vaultAddr
    ) external onlyOwner {
        if (vaultAddr == address(0)) revert InvalidAddress();
        emit SetVault(vault, vaultAddr);
        vault = vaultAddr;
    }

    function withdraw(
        uint256 amount
    ) external onlyTreasurer {
        emit Withdraw(vault, amount);
        vault.sendNative(amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
