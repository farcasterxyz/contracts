// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {USDPriceFeed} from "../../../src/abstract/USDPriceFeed.sol";
import {TransferHelper} from "../../../src/libraries/TransferHelper.sol";
import {USDPriceFeedTestSuite, USDPriceFeedHarness} from "./USDPriceFeedTestSuite.sol";
import {MockChainlinkFeed} from "../../Utils.sol";

/* solhint-disable state-visibility */

contract USDPriceFeedTest is USDPriceFeedTestSuite {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SetPriceFeed(address oldFeed, address newFeed);
    event SetUptimeFeed(address oldFeed, address newFeed);
    event SetPrice(uint256 oldPrice, uint256 newPrice);
    event SetFixedEthUsdPrice(uint256 oldPrice, uint256 newPrice);
    event SetCacheDuration(uint256 oldDuration, uint256 newDuration);
    event SetMaxAge(uint256 oldAge, uint256 newAge);
    event SetMinAnswer(uint256 oldPrice, uint256 newPrice);
    event SetMaxAnswer(uint256 oldPrice, uint256 newPrice);
    event SetGracePeriod(uint256 oldPeriod, uint256 newPeriod);
    event SetVault(address oldVault, address newVault);
    event Withdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZED VALUES
    //////////////////////////////////////////////////////////////*/

    function testVersion() public {
        assertEq(usdPriceFeed.VERSION(), "2025.01.15");
    }

    function testRoles() public {
        assertEq(usdPriceFeed.ownerRoleId(), keccak256("OWNER_ROLE"));
        assertEq(usdPriceFeed.operatorRoleId(), keccak256("OPERATOR_ROLE"));
        assertEq(usdPriceFeed.treasurerRoleId(), keccak256("TREASURER_ROLE"));
    }

    function testDefaultAdmin() public {
        assertTrue(usdPriceFeed.hasRole(usdPriceFeed.DEFAULT_ADMIN_ROLE(), roleAdmin));
    }

    function testPriceFeedDefault() public {
        assertEq(address(usdPriceFeed.priceFeed()), address(priceFeed));
    }

    function testUptimeFeedDefault() public {
        assertEq(address(usdPriceFeed.uptimeFeed()), address(uptimeFeed));
    }

    function testUsdUnitPriceDefault() public {
        assertEq(usdPriceFeed.usdUnitPrice(), INITIAL_USD_UNIT_PRICE);
    }

    function testEthUSDPriceDefault() public {
        assertEq(usdPriceFeed.ethUsdPrice(), uint256(ETH_USD_PRICE));
    }

    function testPrevEthUSDPriceDefault() public {
        assertEq(usdPriceFeed.prevEthUsdPrice(), uint256(ETH_USD_PRICE));
    }

    function testLastPriceFeedUpdateDefault() public {
        assertEq(usdPriceFeed.lastPriceFeedUpdateTime(), block.timestamp);
    }

    function testLastPriceFeedUpdateBlockDefault() public {
        assertEq(usdPriceFeed.lastPriceFeedUpdateBlock(), block.number);
    }

    function testPriceFeedCacheDurationDefault() public {
        assertEq(usdPriceFeed.priceFeedCacheDuration(), INITIAL_PRICE_FEED_CACHE_DURATION);
    }

    function testPriceFeedMaxAgeDefault() public {
        assertEq(usdPriceFeed.priceFeedMaxAge(), INITIAL_PRICE_FEED_MAX_AGE);
    }

    function testPriceFeedMinAnswerDefault() public {
        assertEq(usdPriceFeed.priceFeedMinAnswer(), INITIAL_PRICE_FEED_MIN_ANSWER);
    }

    function testPriceFeedMaxAnswerDefault() public {
        assertEq(usdPriceFeed.priceFeedMaxAnswer(), INITIAL_PRICE_FEED_MAX_ANSWER);
    }

    function testUptimeFeedGracePeriodDefault() public {
        assertEq(usdPriceFeed.uptimeFeedGracePeriod(), INITIAL_UPTIME_FEED_GRACE_PERIOD);
    }

    function testFuzzInitialPrice(
        uint128 quantity
    ) public {
        assertEq(usdPriceFeed.price(quantity), INITIAL_PRICE_IN_ETH * quantity);
    }

    function testInitialUnitPrice() public {
        assertEq(usdPriceFeed.unitPrice(), INITIAL_PRICE_IN_ETH);
    }

    function testInitialPriceUpdate() public {
        // Clear ethUsdPrice storage slot
        vm.store(address(usdPriceFeed), bytes32(uint256(12)), bytes32(0));
        assertEq(usdPriceFeed.ethUsdPrice(), 0);

        // Clear prevEthUsdPrice storage slot
        vm.store(address(usdPriceFeed), bytes32(uint256(13)), bytes32(0));
        assertEq(usdPriceFeed.prevEthUsdPrice(), 0);

        vm.prank(owner);
        usdPriceFeed.refreshPrice();

        assertEq(usdPriceFeed.ethUsdPrice(), uint256(ETH_USD_PRICE));
        assertEq(usdPriceFeed.prevEthUsdPrice(), uint256(ETH_USD_PRICE));
        assertEq(usdPriceFeed.ethUsdPrice(), usdPriceFeed.prevEthUsdPrice());
    }

    /*//////////////////////////////////////////////////////////////
                               UNIT PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzUnitPriceRefresh(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is in bounds
        ethUsdPrice =
            bound(ethUsdPrice, int256(usdPriceFeed.priceFeedMinAnswer()), int256(usdPriceFeed.priceFeedMaxAnswer()));

        priceFeed.setPrice(ethUsdPrice);
        vm.startPrank(owner);
        usdPriceFeed.refreshPrice();
        usdPriceFeed.setPrice(usdUnitPrice);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(usdPriceFeed.unitPrice(), (uint256(usdUnitPrice)).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzUnitPriceCached(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = usdPriceFeed.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);

        vm.prank(owner);
        usdPriceFeed.setPrice(usdUnitPrice);

        assertEq(usdPriceFeed.unitPrice(), (uint256(usdUnitPrice) * 1e18) / cachedPrice);
    }

    /*//////////////////////////////////////////////////////////////
                                  PRICE
    //////////////////////////////////////////////////////////////*/

    function testPriceRoundsUp() public {
        priceFeed.setPrice(1e18 + 1);

        vm.startPrank(owner);
        usdPriceFeed.setMaxAnswer(1e20);
        usdPriceFeed.refreshPrice();
        usdPriceFeed.setPrice(1);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(usdPriceFeed.price(1), 1);
    }

    function testFuzzPrice(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is in bounds
        ethUsdPrice =
            bound(ethUsdPrice, int256(usdPriceFeed.priceFeedMinAnswer()), int256(usdPriceFeed.priceFeedMaxAnswer()));

        priceFeed.setPrice(ethUsdPrice);
        vm.startPrank(owner);
        usdPriceFeed.refreshPrice();
        usdPriceFeed.setPrice(usdUnitPrice);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(usdPriceFeed.price(units), (uint256(usdUnitPrice) * units).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzPriceCached(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = usdPriceFeed.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);
        vm.prank(owner);
        usdPriceFeed.setPrice(usdUnitPrice);

        assertEq(usdPriceFeed.price(units), (uint256(usdUnitPrice) * units).divWadUp(cachedPrice));
    }

    /*//////////////////////////////////////////////////////////////
                               PRICE FEED
    //////////////////////////////////////////////////////////////*/

    function testFuzzPriceFeedRevertsInvalidPrice(
        int256 price
    ) public {
        // Ensure price is zero or negative
        price = price > 0 ? -price : price;
        priceFeed.setPrice(price);

        vm.expectRevert(USDPriceFeed.InvalidPrice.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testPriceFeedRevertsInvalidTimestamp() public {
        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: 2000e8,
                startedAt: block.timestamp,
                timeStamp: block.timestamp + 1,
                answeredInRound: 1
            })
        );
        priceFeed.setStubTimeStamp(true);

        vm.expectRevert(USDPriceFeed.InvalidRoundTimestamp.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testPriceFeedRevertsZeroRoundId() public {
        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 0,
                answer: 2000e8,
                startedAt: block.timestamp,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(USDPriceFeed.IncompleteRound.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testFuzzPriceFeedRevertsAnswerBelowBound(
        uint256 delta
    ) public {
        delta = bound(delta, 1, uint256(usdPriceFeed.priceFeedMinAnswer()) - 1);

        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: int256(usdPriceFeed.priceFeedMinAnswer() - delta),
                startedAt: block.timestamp,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(USDPriceFeed.PriceOutOfBounds.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testPriceFeedRevertsAnswerAboveBound(
        uint256 delta
    ) public {
        delta = bound(delta, 1, uint256(type(int256).max) - usdPriceFeed.priceFeedMaxAnswer());

        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: int256(usdPriceFeed.priceFeedMaxAnswer() + delta),
                startedAt: block.timestamp,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(USDPriceFeed.PriceOutOfBounds.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testPriceFeedRevertsStaleAnswerByMaxAge() public {
        vm.warp(INITIAL_PRICE_FEED_MAX_AGE + 2);

        // Set stale answeredInRound value
        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: 2000e8,
                startedAt: block.timestamp,
                timeStamp: 1,
                answeredInRound: 1
            })
        );
        priceFeed.setStubTimeStamp(true);

        vm.expectRevert(USDPriceFeed.StaleAnswer.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testPriceFeedRevertsIncompleteRound() public {
        // Set zero timeStamp value
        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: 2000e8,
                startedAt: block.timestamp,
                timeStamp: 0,
                answeredInRound: 1
            })
        );
        priceFeed.setStubTimeStamp(true);
        vm.expectRevert(USDPriceFeed.IncompleteRound.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testFuzzPriceFeedFailure(address msgSender, uint128 units) public {
        _assumeClean(msgSender);
        uint256 price = usdPriceFeed.price(units);
        vm.deal(msgSender, price);

        // Fake a price feed error and ensure the next call will refresh the price.
        priceFeed.setShouldRevert(true);
        vm.warp(block.timestamp + usdPriceFeed.priceFeedCacheDuration() + 1);

        // Reading price reverts
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(msgSender);
        usdPriceFeed.readPrice();

        // Owner can set a failsafe fixed price.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, 4000e8);
        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(4000e8);

        // ETH doubled in USD terms, so we need
        // half as much for the same USD price.
        uint256 newPrice = usdPriceFeed.price(units);
        assertEq(newPrice, price / 2);

        // Reading price now succeeds.
        vm.prank(msgSender);
        usdPriceFeed.readPrice();

        // Setting fixed price back to zero re-enables the price feed.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(4000e8, 0);
        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(0);

        // Calls revert again, since price feed is re-enabled.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                               UPTIME FEED
    //////////////////////////////////////////////////////////////*/

    function testFuzzUptimeFeedRevertsSequencerDown(
        int256 answer
    ) public {
        if (answer == 0) ++answer;
        // Set nonzero answer. It's counterintuitive, but a zero answer
        // means the sequencer is up.
        uptimeFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: answer,
                startedAt: 0,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(USDPriceFeed.SequencerDown.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testUptimeFeedRevertsZeroRoundId() public {
        // Set stale answeredInRound value
        uptimeFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 0,
                answer: 0,
                startedAt: block.timestamp,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(USDPriceFeed.IncompleteRound.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testFuzzUptimeFeedRevertsInvalidTimestamp(
        uint256 secondsAhead
    ) public {
        secondsAhead = bound(secondsAhead, 1, type(uint256).max - block.timestamp);

        // Set timestamp in future
        uptimeFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: 0,
                startedAt: 0,
                timeStamp: block.timestamp + secondsAhead,
                answeredInRound: 1
            })
        );
        uptimeFeed.setStubTimeStamp(true);

        vm.expectRevert(USDPriceFeed.InvalidRoundTimestamp.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testUptimeFeedRevertsIncompleteRound() public {
        // Set zero timeStamp value
        uptimeFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: 0,
                startedAt: block.timestamp,
                timeStamp: 0,
                answeredInRound: 1
            })
        );
        uptimeFeed.setStubTimeStamp(true);
        vm.expectRevert(USDPriceFeed.IncompleteRound.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testUptimeFeedRevertsGracePeriodNotOver() public {
        // Set startedAt == timeStamp, meaning the sequencer just restarted.
        uptimeFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 1,
                answer: 0,
                startedAt: block.timestamp,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(USDPriceFeed.GracePeriodNotOver.selector);
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    function testFuzzUptimeFeedFailure(address msgSender, uint128 units) public {
        _assumeClean(msgSender);
        uint256 price = usdPriceFeed.price(units);
        vm.deal(msgSender, price);

        // Fake an uptime feed error and ensure the next call will refresh the price.
        uptimeFeed.setShouldRevert(true);
        vm.warp(block.timestamp + usdPriceFeed.priceFeedCacheDuration() + 1);

        // Reading price reverts
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(msgSender);
        usdPriceFeed.readPrice();

        // Owner can set a failsafe fixed price.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, 4000e8);
        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(4000e8);

        // ETH doubled in USD terms, so we need
        // half as much for the same USD price.
        uint256 newPrice = usdPriceFeed.price(units);
        assertEq(newPrice, price / 2);

        // Reading price now succeeds.
        vm.prank(msgSender);
        usdPriceFeed.readPrice();

        // Setting fixed price back to zero re-enables the price feed.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(4000e8, 0);
        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(0);

        // Calls revert again, since price feed is re-enabled.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(owner);
        usdPriceFeed.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                              REFRESH PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAuthorizedCanRefreshPrice(
        address caller
    ) public {
        vm.assume(caller != owner && caller != treasurer);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.Unauthorized.selector);
        usdPriceFeed.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                           SET DATA FEEDS
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetPriceFeed(address caller, address newFeed) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setPriceFeed(AggregatorV3Interface(newFeed));
    }

    function testFuzzSetPriceFeed(
        address newFeed
    ) public {
        AggregatorV3Interface currentFeed = usdPriceFeed.priceFeed();

        vm.expectEmit();
        emit SetPriceFeed(address(currentFeed), newFeed);

        vm.prank(owner);
        usdPriceFeed.setPriceFeed(AggregatorV3Interface(newFeed));

        assertEq(address(usdPriceFeed.priceFeed()), newFeed);
    }

    function testFuzzOnlyOwnerCanSetUptimeFeed(address caller, address newFeed) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setUptimeFeed(AggregatorV3Interface(newFeed));
    }

    function testFuzzSetUptimeFeed(
        address newFeed
    ) public {
        AggregatorV3Interface currentFeed = usdPriceFeed.uptimeFeed();

        vm.expectEmit();
        emit SetUptimeFeed(address(currentFeed), newFeed);

        vm.prank(owner);
        usdPriceFeed.setUptimeFeed(AggregatorV3Interface(newFeed));

        assertEq(address(usdPriceFeed.uptimeFeed()), newFeed);
    }

    /*//////////////////////////////////////////////////////////////
                           SET USD UNIT PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetUSDUnitPrice(address caller, uint256 unitPrice) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setPrice(unitPrice);
    }

    function testFuzzSetUSDUnitPrice(
        uint256 unitPrice
    ) public {
        uint256 currentPrice = usdPriceFeed.usdUnitPrice();

        vm.expectEmit(false, false, false, true);
        emit SetPrice(currentPrice, unitPrice);

        vm.prank(owner);
        usdPriceFeed.setPrice(unitPrice);

        assertEq(usdPriceFeed.usdUnitPrice(), unitPrice);
    }

    /*//////////////////////////////////////////////////////////////
                           SET FIXED ETH PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetFixedEthUsdPrice(address caller, uint256 fixedPrice) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setFixedEthUsdPrice(fixedPrice);
    }

    function testFuzzSetFixedEthUsdPrice(
        uint256 fixedPrice
    ) public {
        fixedPrice = bound(fixedPrice, usdPriceFeed.priceFeedMinAnswer(), usdPriceFeed.priceFeedMaxAnswer());
        assertEq(usdPriceFeed.fixedEthUsdPrice(), 0);

        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, fixedPrice);

        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(fixedPrice);

        assertEq(usdPriceFeed.fixedEthUsdPrice(), fixedPrice);
    }

    function testFuzzSetFixedEthUsdPriceRevertsLessThanMinPrice(
        uint256 fixedPrice
    ) public {
        fixedPrice = bound(fixedPrice, 1, usdPriceFeed.priceFeedMinAnswer() - 1);
        assertEq(usdPriceFeed.fixedEthUsdPrice(), 0);

        vm.prank(owner);
        vm.expectRevert(USDPriceFeed.InvalidFixedPrice.selector);
        usdPriceFeed.setFixedEthUsdPrice(fixedPrice);
    }

    function testFuzzSetFixedEthUsdPriceRevertsGreaterThanMaxPrice(
        uint256 fixedPrice
    ) public {
        fixedPrice = bound(fixedPrice, usdPriceFeed.priceFeedMaxAnswer() + 1, type(uint256).max);
        assertEq(usdPriceFeed.fixedEthUsdPrice(), 0);

        vm.prank(owner);
        vm.expectRevert(USDPriceFeed.InvalidFixedPrice.selector);
        usdPriceFeed.setFixedEthUsdPrice(fixedPrice);
    }

    function testFuzzSetFixedEthUsdPriceOverridesPriceFeed(
        uint256 fixedPrice
    ) public {
        fixedPrice = bound(fixedPrice, usdPriceFeed.priceFeedMinAnswer(), usdPriceFeed.priceFeedMaxAnswer());
        vm.assume(fixedPrice != usdPriceFeed.ethUsdPrice());
        fixedPrice = bound(fixedPrice, 1, type(uint256).max);

        uint256 usdUnitPrice = usdPriceFeed.usdUnitPrice();
        uint256 priceBefore = usdPriceFeed.unitPrice();

        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(fixedPrice);

        uint256 priceAfter = usdPriceFeed.unitPrice();

        assertTrue(priceBefore != priceAfter);
        assertEq(priceAfter, usdUnitPrice.divWadUp(fixedPrice));
    }

    function testFuzzRemoveFixedEthUsdPriceReenablesPriceFeed(
        uint256 fixedPrice
    ) public {
        fixedPrice = bound(fixedPrice, usdPriceFeed.priceFeedMinAnswer(), usdPriceFeed.priceFeedMaxAnswer());
        vm.assume(fixedPrice != usdPriceFeed.ethUsdPrice());
        fixedPrice = bound(fixedPrice, 1, type(uint256).max);

        uint256 usdUnitPrice = usdPriceFeed.usdUnitPrice();
        uint256 priceBefore = usdPriceFeed.unitPrice();

        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(fixedPrice);

        uint256 priceAfter = usdPriceFeed.unitPrice();

        assertTrue(priceBefore != priceAfter);
        assertEq(priceAfter, usdUnitPrice.divWadUp(fixedPrice));

        vm.prank(owner);
        usdPriceFeed.setFixedEthUsdPrice(0);
        assertEq(usdPriceFeed.fixedEthUsdPrice(), 0);

        uint256 priceFinal = usdPriceFeed.unitPrice();
        assertEq(priceBefore, priceFinal);
    }

    /*//////////////////////////////////////////////////////////////
                           SET CACHE DURATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetCacheDuration(address caller, uint256 duration) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setCacheDuration(duration);
    }

    function testFuzzSetCacheDuration(
        uint256 duration
    ) public {
        uint256 currentDuration = usdPriceFeed.priceFeedCacheDuration();

        vm.expectEmit(false, false, false, true);
        emit SetCacheDuration(currentDuration, duration);

        vm.prank(owner);
        usdPriceFeed.setCacheDuration(duration);

        assertEq(usdPriceFeed.priceFeedCacheDuration(), duration);
    }

    /*//////////////////////////////////////////////////////////////
                           SET MAX PRICE AGE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetMaxAge(address caller, uint256 age) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setMaxAge(age);
    }

    function testFuzzSetMaxAge(
        uint256 age
    ) public {
        uint256 currentAge = usdPriceFeed.priceFeedMaxAge();

        vm.expectEmit(false, false, false, true);
        emit SetMaxAge(currentAge, age);

        vm.prank(owner);
        usdPriceFeed.setMaxAge(age);

        assertEq(usdPriceFeed.priceFeedMaxAge(), age);
    }

    /*//////////////////////////////////////////////////////////////
                           SET PRICE BOUNDS
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetMinAnswer(address caller, uint256 answer) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setMinAnswer(answer);
    }

    function testFuzzSetMinAnswer(
        uint256 answer
    ) public {
        answer = bound(answer, 0, usdPriceFeed.priceFeedMaxAnswer() - 1);
        uint256 currentMin = usdPriceFeed.priceFeedMinAnswer();

        vm.expectEmit(false, false, false, true);
        emit SetMinAnswer(currentMin, answer);

        vm.prank(owner);
        usdPriceFeed.setMinAnswer(answer);

        assertEq(usdPriceFeed.priceFeedMinAnswer(), answer);
    }

    function testFuzzCannotSetMinEqualOrAboveMax(
        uint256 answer
    ) public {
        answer = bound(answer, usdPriceFeed.priceFeedMaxAnswer(), type(uint256).max);

        vm.prank(owner);
        vm.expectRevert(USDPriceFeed.InvalidMinAnswer.selector);
        usdPriceFeed.setMinAnswer(answer);
    }

    function testFuzzOnlyOwnerCanSetMaxAnswer(address caller, uint256 answer) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setMaxAnswer(answer);
    }

    function testFuzzSetMaxAnswer(
        uint256 answer
    ) public {
        answer = bound(answer, usdPriceFeed.priceFeedMinAnswer() + 1, type(uint256).max);
        uint256 currentMax = usdPriceFeed.priceFeedMaxAnswer();

        vm.expectEmit(false, false, false, true);
        emit SetMaxAnswer(currentMax, answer);

        vm.prank(owner);
        usdPriceFeed.setMaxAnswer(answer);

        assertEq(usdPriceFeed.priceFeedMaxAnswer(), answer);
    }

    function testFuzzCannotSetMaxEqualOrBelowMin(
        uint256 answer
    ) public {
        answer = bound(answer, 0, usdPriceFeed.priceFeedMinAnswer());

        vm.prank(owner);
        vm.expectRevert(USDPriceFeed.InvalidMaxAnswer.selector);
        usdPriceFeed.setMaxAnswer(answer);
    }

    /*//////////////////////////////////////////////////////////////
                            SET GRACE PERIOD
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetGracePeriod(address caller, uint256 duration) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setGracePeriod(duration);
    }

    function testFuzzSetGracePeriod(
        uint256 duration
    ) public {
        uint256 currentGracePeriod = usdPriceFeed.uptimeFeedGracePeriod();

        vm.expectEmit(false, false, false, true);
        emit SetGracePeriod(currentGracePeriod, duration);

        vm.prank(owner);
        usdPriceFeed.setGracePeriod(duration);

        assertEq(usdPriceFeed.uptimeFeedGracePeriod(), duration);
    }

    /*//////////////////////////////////////////////////////////////
                                SET VAULT
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetVault(
        address newVault
    ) public {
        vm.assume(newVault != address(0));
        vm.expectEmit(false, false, false, true);
        emit SetVault(vault, newVault);

        vm.prank(owner);
        usdPriceFeed.setVault(newVault);

        assertEq(usdPriceFeed.vault(), newVault);
    }

    function testFuzzOnlyOwnerCanSetVault(address caller, address vault) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.setVault(vault);
    }

    function testSetVaultCannotBeZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(USDPriceFeed.InvalidAddress.selector);
        usdPriceFeed.setVault(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                             PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function testPauseUnpause() public {
        assertEq(usdPriceFeed.paused(), false);

        vm.prank(owner);
        usdPriceFeed.pause();

        assertEq(usdPriceFeed.paused(), true);

        vm.prank(owner);
        usdPriceFeed.unpause();

        assertEq(usdPriceFeed.paused(), false);
    }

    function testFuzzOnlyOwnerCanPause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.pause();
    }

    function testFuzzOnlyOwnerCanUnpause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotOwner.selector);
        usdPriceFeed.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function testFuzzWithdrawalRevertsInsufficientFunds(
        uint256 amount
    ) public {
        // Ensure amount is >=0 and deal a smaller amount to the contract
        amount = bound(amount, 1, type(uint256).max);
        vm.deal(address(usdPriceFeed), amount - 1);

        vm.prank(treasurer);
        vm.expectRevert(TransferHelper.CallFailed.selector);
        usdPriceFeed.withdraw(amount);
    }

    function testFuzzWithdrawalRevertsCallFailed(
        uint256 amount
    ) public {
        vm.deal(address(usdPriceFeed), amount);

        vm.prank(owner);
        usdPriceFeed.setVault(address(revertOnReceive));

        vm.prank(treasurer);
        vm.expectRevert(TransferHelper.CallFailed.selector);
        usdPriceFeed.withdraw(amount);
    }

    function testFuzzOnlyTreasurerCanWithdraw(address caller, uint256 amount) public {
        vm.assume(caller != treasurer);
        vm.deal(address(usdPriceFeed), amount);

        vm.prank(caller);
        vm.expectRevert(USDPriceFeed.NotTreasurer.selector);
        usdPriceFeed.withdraw(amount);
    }

    function testFuzzWithdraw(
        uint256 amount
    ) public {
        // Deal an amount > 1 wei so we can withraw at least 1
        amount = bound(amount, 2, type(uint256).max);
        vm.deal(address(usdPriceFeed), amount);
        uint256 balanceBefore = address(vault).balance;

        // Withdraw at last 1 wei
        uint256 withdrawalAmount = bound(amount, 1, amount - 1);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(vault, withdrawalAmount);

        vm.prank(treasurer);
        usdPriceFeed.withdraw(withdrawalAmount);

        uint256 balanceChange = address(vault).balance - balanceBefore;
        assertEq(balanceChange, withdrawalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /* solhint-disable-next-line no-empty-blocks */
    receive() external payable {}
}
