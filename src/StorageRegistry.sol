// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

contract StorageRegistry is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller attempts to rent storage after this contract is deprecated.
    error ContractDeprecated();

    /// @dev Revert if the caller attempts to rent more storage than is available.
    error ExceedsCapacity();

    /// @dev Revert if the caller attempts a batch rent with mismatched input array lengths or an empty array.
    error InvalidBatchInput();

    /// @dev Revert if the caller provides the wrong payment amount.
    error InvalidPayment();

    /// @dev Revert when there are not enough funds for a native token transfer.
    error InsufficientFunds();

    /// @dev Revert when a native token transfer fails.
    error CallFailed();

    /// @dev Revert if the price feed returns a stale price.
    error StalePrice();

    /// @dev Revert if the price feed round is incomplete and has not yet generated a price.
    error IncompleteRound();

    /// @dev Revert if the price feed returns a zero or negative price.
    error InvalidPrice();

    /// @dev Revert if the sequencer uptime feed detects that the L2 sequencer is unavailable.
    error SequencerDown();

    /// @dev Revert if the L2 sequencer restarted less than L2_DOWNTIME_GRACE_PERIOD seconds ago.
    error GracePeriodNotOver();

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
     * @dev Emit an event when an owner changes the price of storage units.
     *
     * @param oldPrice The previous unit price in USD. Fixed point value with 8 decimals.
     * @param newPrice The new unit price in USD. Fixed point value with 8 decimals.
     */
    event SetPrice(uint256 oldPrice, uint256 newPrice);

    /**
     * @dev Emit an event when an owner changes the maximum supply of storage units.
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
     * @dev Emit an event when an owner makes a withdrawal from the contract balance.
     *
     * @param to     Address of recipient.
     * @param amount The amount of ether withdrawn.
     */
    event Withdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Period in seconds to wait after the L2 sequencer restarts before resuming rentals.
     */
    uint256 public constant L2_DOWNTIME_GRACE_PERIOD = 3600;

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
                                 STORAGE
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
     * @dev Total capacity of storage units. Changeable by owner.
     */
    uint256 public maxUnits;

    /**
     * @dev Total number of storage units that have been rented.
     */
    uint256 public rentedUnits;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the price feed, uptime feed, and initial parameters.
     *
     * @param _priceFeed                Chainlink ETH/USD price feed.
     * @param _uptimeFeed               Chainlink L2 sequencer uptime feed.
     * @param _initialDeprecationPeriod Initial deprecation period in seconds.
     * @param _initialUsdUnitPrice      Initial unit price in USD. Fixed point value with 8 decimals.
     * @param _initialMaxUnits          Initial maximum capacity in storage units.
     */
    constructor(
        AggregatorV3Interface _priceFeed,
        AggregatorV3Interface _uptimeFeed,
        uint256 _initialDeprecationPeriod,
        uint256 _initialUsdUnitPrice,
        uint256 _initialMaxUnits
    ) Ownable2Step() {
        priceFeed = _priceFeed;
        uptimeFeed = _uptimeFeed;
        deprecationTimestamp = block.timestamp + _initialDeprecationPeriod;
        usdUnitPrice = _initialUsdUnitPrice;
        maxUnits = _initialMaxUnits;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier whenNotDeprecated() {
        if (block.timestamp >= deprecationTimestamp) revert ContractDeprecated();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE RENTAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Rent storage for a given fid. The caller must provide an exact payment amount.
     *
     * @param fid   The fid that will receive the storage allocation.
     * @param units Number of storage units to rent.
     */
    function rent(uint256 fid, uint256 units) external payable whenNotDeprecated {
        if (msg.value != price(units)) revert InvalidPayment();
        if (rentedUnits + units > maxUnits) revert ExceedsCapacity();

        rentedUnits += units;
        emit Rent(msg.sender, fid, units);
    }

    /**
     * @notice Rent storage for multiple fids. The caller must provide an exact payment amount equal to
     *         the sum of the prices for each fid's storage allocation.
     *
     * @param fids  An array of fids.
     * @param units An array of storage unit quantities. Must be the same length as the fids array.
     */
    function batchRent(uint256[] calldata fids, uint256[] calldata units) external payable whenNotDeprecated {
        if (fids.length == 0 || units.length == 0) revert InvalidBatchInput();
        if (fids.length != units.length) revert InvalidBatchInput();

        uint256 _ethUsdPrice = ethUsdPrice();
        uint256 _usdUnitPrice = usdUnitPrice;

        uint256 totalCost;
        for (uint256 i; i < fids.length; ++i) {
            uint256 qty = units[i];
            if (qty == 0) continue;
            if (rentedUnits + qty > maxUnits) revert ExceedsCapacity();
            totalCost += _price(qty, _usdUnitPrice, _ethUsdPrice);
            rentedUnits += qty;
            emit Rent(msg.sender, fids[i], qty);
        }

        if (msg.value != totalCost) revert InvalidPayment();
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cost in wei to rent one storage unit.
     */
    function unitPrice() public view returns (uint256) {
        return price(1);
    }

    /**
     * @notice Calculate the cost in wei to rent the given number of storage units.
     *
     * @param units Number of storage units.
     */
    function price(uint256 units) public view returns (uint256) {
        return _price(units, usdUnitPrice, ethUsdPrice());
    }

    function ethUsdPrice() public view returns (uint256) {
        /* Ensure that the L2 sequencer is up. */
        (, int256 sequencerUp, uint256 startedAt,,) = uptimeFeed.latestRoundData();
        if (sequencerUp != 0) revert SequencerDown();

        /* If the L2 sequencer recently restarted, ensure the grace period has elapsed. */
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp < L2_DOWNTIME_GRACE_PERIOD) revert GracePeriodNotOver();

        /* Get and validate the Chainlink ETH/USD price. */
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0) revert IncompleteRound();
        if (answeredInRound < roundId) revert StalePrice();

        return uint256(answer);
    }

    function _price(uint256 units, uint256 usdPerUnit, uint256 ethPerUsd) internal pure returns (uint256) {
        return units * usdPerUnit * 1e18 / ethPerUsd;
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Credit a list of fids with free storage units. Only callable by owner.
     *
     * @param fids  An array of fids.
     * @param units Number of storage units per fid.
     */
    function batchCredit(uint256[] calldata fids, uint256 units) external onlyOwner whenNotDeprecated {
        uint256 totalUnits = fids.length * units;
        if (rentedUnits + totalUnits > maxUnits) revert ExceedsCapacity();
        rentedUnits += totalUnits;
        for (uint256 i; i < fids.length; ++i) {
            emit Rent(msg.sender, fids[i], units);
        }
    }

    /**
     * @notice Change the USD price per storage unit.
     *
     * @param usdPrice The new unit price in USD. Fixed point value with 8 decimals.
     */
    function setPrice(uint256 usdPrice) external onlyOwner {
        emit SetPrice(usdUnitPrice, usdPrice);
        usdUnitPrice = usdPrice;
    }

    /**
     * @notice Change the maximum supply of storage units.
     *
     * @param max The new maximum supply of storage units.
     */
    function setMaxUnits(uint256 max) external onlyOwner {
        emit SetMaxUnits(maxUnits, max);
        maxUnits = max;
    }

    /**
     * @notice Change the deprecationTimestamp.
     *
     * @param timestamp The new deprecationTimestamp.
     */
    function setDeprecationTimestamp(uint256 timestamp) external onlyOwner {
        emit SetDeprecationTimestamp(deprecationTimestamp, timestamp);
        deprecationTimestamp = timestamp;
    }

    /**
     * @notice Withdraw a specified amount of ether from the contract balance to a given address.
     *
     * @param to     Address of recipient.
     * @param amount The amount of ether to withdraw.
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        if (address(this).balance < amount) revert InsufficientFunds();
        emit Withdraw(to, amount);
        (bool success,) = payable(to).call{value: amount}("");
        if (!success) revert CallFailed();
    }
}
