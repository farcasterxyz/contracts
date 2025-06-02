// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {StorageRegistryHarness, MockPriceFeed, MockUptimeFeed, MockChainlinkFeed, RevertOnReceive} from "../Utils.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";

/* solhint-disable state-visibility */

abstract contract StorageRegistryTestSuite is TestSuiteSetup {
    StorageRegistryHarness internal storageRegistry;
    MockPriceFeed internal priceFeed;
    MockUptimeFeed internal uptimeFeed;
    RevertOnReceive internal revertOnReceive;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address internal deployer = address(this);
    address internal mallory = makeAddr("mallory");
    address internal vault = makeAddr("vault");
    address internal roleAdmin = makeAddr("roleAdmin");
    address internal operator = makeAddr("operator");
    address internal treasurer = makeAddr("treasurer");

    uint256 internal immutable DEPLOYED_AT = block.timestamp + 3600;

    uint256 internal constant INITIAL_RENTAL_PERIOD = 365 days;
    uint256 internal constant INITIAL_USD_UNIT_PRICE = 5e8; // $5 USD
    uint256 internal constant INITIAL_MAX_UNITS = 2_000_000;

    int256 internal constant SEQUENCER_UP = 0;
    int256 internal constant ETH_USD_PRICE = 2000e8; // $2000 USD/ETH

    uint256 internal constant INITIAL_PRICE_FEED_CACHE_DURATION = 1 days;
    uint256 internal constant INITIAL_PRICE_FEED_MAX_AGE = 2 hours;
    uint256 internal constant INITIAL_UPTIME_FEED_GRACE_PERIOD = 1 hours;
    uint256 internal constant INITIAL_PRICE_IN_ETH = 0.0025 ether;
    uint256 internal constant INITIAL_PRICE_FEED_MIN_ANSWER = 100e8; // $100 USD
    uint256 internal constant INITIAL_PRICE_FEED_MAX_ANSWER = 10_000e8; // $10k USD

    function setUp() public virtual override {
        super.setUp();

        priceFeed = new MockPriceFeed();
        uptimeFeed = new MockUptimeFeed();
        revertOnReceive = new RevertOnReceive();

        uptimeFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: SEQUENCER_UP,
                startedAt: 0,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: ETH_USD_PRICE,
                startedAt: 0,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.warp(DEPLOYED_AT);

        storageRegistry = new StorageRegistryHarness(
            priceFeed,
            uptimeFeed,
            INITIAL_USD_UNIT_PRICE,
            INITIAL_MAX_UNITS,
            vault,
            roleAdmin,
            owner,
            operator,
            treasurer
        );

        addKnownContract(address(priceFeed));
        addKnownContract(address(uptimeFeed));
        addKnownContract(address(revertOnReceive));
        addKnownContract(address(storageRegistry));
    }
}
