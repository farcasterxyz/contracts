// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {StorageRegistryHarness, MockPriceFeed, MockUptimeFeed, MockChainlinkFeed, RevertOnReceive} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract StorageRegistryTestSuite is Test {
    StorageRegistryHarness internal fcStorage;
    MockPriceFeed internal priceFeed;
    MockUptimeFeed internal uptimeFeed;
    RevertOnReceive internal revertOnReceive;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address internal owner = address(this);
    address internal mallory = makeAddr("mallory");

    uint256 internal immutable DEPLOYED_AT = block.timestamp + 3600;

    uint256 internal constant INITIAL_RENTAL_PERIOD = 365 days;
    uint256 internal constant INITIAL_USD_UNIT_PRICE = 5e8; // $5 USD
    uint256 internal constant INITIAL_MAX_UNITS = 2_000_000;

    int256 internal constant SEQUENCER_UP = 0;
    int256 internal constant ETH_USD_PRICE = 2000e8; // $2000 USD/ETH

    uint256 internal constant INITIAL_PRICE_FEED_CACHE_DURATION = 1 days;
    uint256 internal constant INITIAL_PRICE_IN_ETH = 0.0025 ether;

    function setUp() public {
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

        fcStorage = new StorageRegistryHarness(
            priceFeed,
            uptimeFeed,
            INITIAL_RENTAL_PERIOD,
            INITIAL_USD_UNIT_PRICE,
            INITIAL_MAX_UNITS,
            INITIAL_PRICE_FEED_CACHE_DURATION
        );
    }
}