// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {AccessControlEnumerable} from "openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

contract StorageRent is AccessControlEnumerable {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller attempts to rent storage after this contract is deprecated.
    error ContractDeprecated();

    /// @dev Revert if the caller attempts to rent more storage than is available.
    error ExceedsCapacity();

    /// @dev Revert if the caller attempts to rent zero units.
    error InvalidAmount();

    /// @dev Revert if the caller attempts a batch rent with mismatched input array lengths or an empty array.
    error InvalidBatchInput();

    /// @dev Revert if the caller provides the wrong payment amount.
    error InvalidPayment();

    /// @dev Revert when there are not enough funds for a native token transfer.
    error InsufficientFunds();

    /// @dev Revert when a native token transfer fails.
    error CallFailed();

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

    /// @dev Revert if the depreaction timestamp parameter is in the past.
    error InvalidDeprecationTimestamp();

    /// @dev Revert if the max units parameter is above 1.6e7 (64TB @ 4MB/unit).
    error InvalidMaxUnits();

    /// @dev Revert if the caller is not an admin.
    error NotAdmin();

    /// @dev Revert if the caller is not an operator.
    error NotOperator();

    /// @dev Revert if the caller is not a treasurer.
    error NotTreasurer();

    /// @dev Revert if the caller does not have an authorized role.
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when caller pays rent for an fid's storage.
     *
     * @param payer     Address of the account paying the storage rent.
     * @param fid       The fid that will receive the storage allocation.
     * @param units     The number of storage units being rented.
     */
    event Rent(address indexed payer, uint256 indexed fid, uint256 units);

    /**
     * @dev Emit an event when an admin changes the price of storage units.
     *
     * @param oldPrice The previous unit price in USD. Fixed point value with 8 decimals.
     * @param newPrice The new unit price in USD. Fixed point value with 8 decimals.
     */
    event SetPrice(uint256 oldPrice, uint256 newPrice);

    /**
     * @dev Emit an event when an admin changes the maximum supply of storage units.
     *
     * @param oldMax The previous maximum amount.
     * @param newMax The new maximum amount.
     */
    event SetMaxUnits(uint256 oldMax, uint256 newMax);

    /**
     * @dev Emit an event when an admin changes the deprecationTimestamp.
     *
     * @param oldTimestamp The previous deprecationTimestamp.
     * @param newTimestamp The new deprecationTimestamp.
     */
    event SetDeprecationTimestamp(uint256 oldTimestamp, uint256 newTimestamp);

    /**
     * @dev Emit an event when an admin changes the priceFeedCacheDuration.
     *
     * @param oldDuration The previous priceFeedCacheDuration.
     * @param newDuration The new priceFeedCacheDuration.
     */
    event SetCacheDuration(uint256 oldDuration, uint256 newDuration);

    /**
     * @dev Emit an event when an admin changes the uptimeFeedGracePeriod.
     *
     * @param oldPeriod The previous uptimeFeedGracePeriod.
     * @param newPeriod The new uptimeFeedGracePeriod.
     */
    event SetGracePeriod(uint256 oldPeriod, uint256 newPeriod);

    /**
     * @dev Emit an event when an admin changes the vault.
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
     * @dev Contract version. Follows Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.07.12";

    /**
     * @dev Total possile storage unit capacity. 1.6e7 = 64TB @ 4MB/unit .
     */
    uint256 public constant TOTAL_STORAGE_UNIT_CAPACITY = 1.6e7;

    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
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
     * @dev Block timestamp at which this contract will no longer accept storage rent payments. Changeable by admin.
     */
    uint256 public deprecationTimestamp;

    /**
     * @dev Price per storage unit in USD. Fixed point value with 8 decimals, e.g. 5e8 = $5 USD. Changeable by admin.
     */
    uint256 public usdUnitPrice;

    /**
     * @dev Total capacity of storage units. Changeable by admin.
     */
    uint256 public maxUnits;

    /**
     * @dev Duration to cache ethUsdPrice before updating from the price feed. Changeable by admin.
     */
    uint256 public priceFeedCacheDuration;

    /**
     * @dev Period in seconds to wait after the L2 sequencer restarts before resuming rentals.
     *      See: https://docs.chain.link/data-feeds/l2-sequencer-feeds. Changeable by admin.
     */
    uint256 public uptimeFeedGracePeriod;

    /**
     * @dev Address to which the treasurer role can withdraw funds. Changeable by admin.
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
     * @param _initialAdmin                  Initial admin address.
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
        address _initialAdmin,
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

        uptimeFeedGracePeriod = 1 hours;
        emit SetGracePeriod(0, 1 hours);

        vault = _initialVault;
        emit SetVault(address(0), _initialVault);

        _grantRole(DEFAULT_ADMIN_ROLE, _initialRoleAdmin);
        _grantRole(ADMIN_ROLE, _initialAdmin);
        _grantRole(OPERATOR_ROLE, _initialOperator);
        _grantRole(TREASURER_ROLE, _initialTreasurer);

        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier whenNotDeprecated() {
        if (block.timestamp >= deprecationTimestamp) revert ContractDeprecated();
        _;
    }

    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
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
     * @notice Rent storage for a given fid. The caller must provide at
     *         least price(units) wei of payment. Any excess payment will
     *         be refunded to the caller.
     *
     * @param fid   The fid that will receive the storage allocation.
     * @param units Number of storage units to rent.
     */
    function rent(uint256 fid, uint256 units) external payable whenNotDeprecated {
        // Checks
        if (units == 0) revert InvalidAmount();
        if (rentedUnits + units > maxUnits) revert ExceedsCapacity();
        uint256 totalPrice = _price(units);
        if (msg.value < totalPrice) revert InvalidPayment();

        // Effects
        rentedUnits += units;
        emit Rent(msg.sender, fid, units);

        // Interactions
        if (msg.value > totalPrice) {
            _sendNative(msg.sender, msg.value - totalPrice);
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
            _sendNative(msg.sender, msg.value - totalPrice);
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
        uint256 ethPrice = (lastPriceFeedUpdateBlock == block.number) ? prevEthUsdPrice : ethUsdPrice;
        return _price(units, usdUnitPrice, ethPrice);
    }

    /**
     * @dev Return the cached ethUsdPrice if it's still valid, otherwise get the
     *      latest ETH/USD price from the price feed and update the cache.
     */
    function _ethUsdPrice() internal returns (uint256) {
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
         *  block. If we updated the price in this block, use the previous price
         *  until the next block. Otherwise, use the latest price.
         */
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

        /* Get and validate the Chainlink ETH/USD price. */
        (uint80 priceRoundId, int256 answer,, uint256 priceUpdatedAt, uint80 priceAnsweredInRound) =
            priceFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (priceUpdatedAt == 0) revert IncompleteRound();
        if (priceAnsweredInRound < priceRoundId) revert StaleAnswer();

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
     * @param ethPerUsd  ETH/USD price. Fixed point with 8 decimals.
     *
     * @return uint256 price in wei, i.e. 18 decimals.
     */
    function _price(uint256 units, uint256 usdPerUnit, uint256 ethPerUsd) internal pure returns (uint256) {
        return (units * usdPerUnit).divWadUp(ethPerUsd);
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
     * @notice Force refresh the cached Chainlink ETH/USD price. Callable by admin and treasurer.
     */
    function refreshPrice() external {
        if (!hasRole(ADMIN_ROLE, msg.sender) && !hasRole(TREASURER_ROLE, msg.sender)) revert Unauthorized();
        _refreshPrice();
    }

    /**
     * @notice Change the USD price per storage unit. Callable by admin and treasurer.
     *
     * @param usdPrice The new unit price in USD. Fixed point value with 8 decimals.
     */
    function setPrice(uint256 usdPrice) external {
        if (!hasRole(ADMIN_ROLE, msg.sender) && !hasRole(TREASURER_ROLE, msg.sender)) revert Unauthorized();
        emit SetPrice(usdUnitPrice, usdPrice);
        usdUnitPrice = usdPrice;
    }

    /**
     * @notice Change the maximum supply of storage units. Only callable by admin.
     *
     * @param max The new maximum supply of storage units.
     */
    function setMaxUnits(uint256 max) external onlyAdmin {
        if (max > TOTAL_STORAGE_UNIT_CAPACITY) revert InvalidMaxUnits();
        emit SetMaxUnits(maxUnits, max);
        maxUnits = max;
    }

    /**
     * @notice Change the deprecationTimestamp. Only callable by admin.
     *
     * @param timestamp The new deprecationTimestamp.
     */
    function setDeprecationTimestamp(uint256 timestamp) external onlyAdmin {
        if (timestamp < block.timestamp) revert InvalidDeprecationTimestamp();
        emit SetDeprecationTimestamp(deprecationTimestamp, timestamp);
        deprecationTimestamp = timestamp;
    }

    /**
     * @notice Change the priceFeedCacheDuration. Only callable by admin.
     *
     * @param duration The new priceFeedCacheDuration.
     */
    function setCacheDuration(uint256 duration) external onlyAdmin {
        emit SetCacheDuration(priceFeedCacheDuration, duration);
        priceFeedCacheDuration = duration;
    }

    /**
     * @notice Change the uptimeFeedGracePeriod. Only callable by admin.
     *
     * @param period The new uptimeFeedGracePeriod.
     */
    function setGracePeriod(uint256 period) external onlyAdmin {
        emit SetGracePeriod(uptimeFeedGracePeriod, period);
        uptimeFeedGracePeriod = period;
    }

    /**
     * @notice Set the vault address that can receive funds from this contract.
     *         Only callable by admin.
     *
     * @param vaultAddr The new vault address.
     */
    function setVault(address vaultAddr) external onlyAdmin {
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
        _sendNative(vault, amount);
    }

    /**
     * @dev Native token transfer helper.
     */
    function _sendNative(address to, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientFunds();
        (bool success,) = payable(to).call{value: amount}("");
        if (!success) revert CallFailed();
    }
}
