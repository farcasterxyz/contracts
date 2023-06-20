// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import "../TestConstants.sol";

import {StorageRent} from "../../src/StorageRent.sol";
import {StorageRentTestSuite} from "./StorageRentTestSuite.sol";
import {MockChainlinkFeed} from "../Utils.sol";

/* solhint-disable state-visibility */

contract StorageRentTest is StorageRentTestSuite {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Rent(address indexed buyer, uint256 indexed id, uint256 units);
    event SetPrice(uint256 oldPrice, uint256 newPrice);
    event SetMaxUnits(uint256 oldMax, uint256 newMax);
    event SetDeprecationTimestamp(uint256 oldTimestamp, uint256 newTimestamp);
    event SetCacheDuration(uint256 oldDuration, uint256 newDuration);
    event SetGracePeriod(uint256 oldPeriod, uint256 newPeriod);
    event Withdraw(address indexed to, uint256 amount);

    function testVersion() public {
        assertEq(fcStorage.VERSION(), "2023.06.01");
    }

    function testOwnerDefault() public {
        assertEq(fcStorage.owner(), owner);
    }

    function testPriceFeedDefault() public {
        assertEq(address(fcStorage.priceFeed()), address(priceFeed));
    }

    function testUptimeFeedDefault() public {
        assertEq(address(fcStorage.uptimeFeed()), address(uptimeFeed));
    }

    function testDeprecationTimestampDefault() public {
        assertEq(fcStorage.deprecationTimestamp(), DEPLOYED_AT + INITIAL_RENTAL_PERIOD);
    }

    function testUsdUnitPriceDefault() public {
        assertEq(fcStorage.usdUnitPrice(), INITIAL_USD_UNIT_PRICE);
    }

    function testMaxUnitsDefault() public {
        assertEq(fcStorage.maxUnits(), INITIAL_MAX_UNITS);
    }

    function testRentedUnitsDefault() public {
        assertEq(fcStorage.rentedUnits(), 0);
    }

    function testEthUSDPriceDefault() public {
        assertEq(fcStorage.ethUsdPrice(), uint256(ETH_USD_PRICE));
    }

    function testLastPriceFeedUpdateDefault() public {
        assertEq(fcStorage.lastPriceFeedUpdate(), block.timestamp);
    }

    function testPriceFeedCacheDurationDefault() public {
        assertEq(fcStorage.priceFeedCacheDuration(), INITIAL_PRICE_FEED_CACHE_DURATION);
    }

    function testUptimeFeedGracePeriodDefault() public {
        assertEq(fcStorage.uptimeFeedGracePeriod(), INITIAL_UPTIME_FEED_GRACE_PERIOD);
    }

    function testFuzzRent(address msgSender, uint256 id, uint200 units) public {
        rentStorage(msgSender, id, units);
    }

    function testFuzzRentRevertsZeroUnits(address msgSender, uint256 id) public {
        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidAmount.selector);
        fcStorage.rent(id, 0);
    }

    function testFuzzRentCachedPrice(
        address msgSender1,
        uint256 id1,
        uint200 units1,
        address msgSender2,
        uint256 id2,
        uint200 units2,
        int256 newEthUsdPrice,
        uint256 warp
    ) public {
        uint256 lastPriceFeedUpdate = fcStorage.lastPriceFeedUpdate();
        uint256 ethUsdPrice = fcStorage.ethUsdPrice();

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        rentStorage(msgSender1, id1, units1);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        warp = bound(warp, 0, fcStorage.priceFeedCacheDuration());
        vm.warp(block.timestamp + warp);

        rentStorage(msgSender2, id2, units2);

        assertEq(fcStorage.lastPriceFeedUpdate(), lastPriceFeedUpdate);
        assertEq(fcStorage.ethUsdPrice(), ethUsdPrice);
    }

    function testFuzzRentPriceRefresh(
        address msgSender1,
        uint256 id1,
        uint200 units1,
        address msgSender2,
        uint256 id2,
        uint200 units2,
        int256 newEthUsdPrice
    ) public {
        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        rentStorage(msgSender1, id1, units1);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        vm.warp(block.timestamp + fcStorage.priceFeedCacheDuration() + 1);

        rentStorage(msgSender2, id2, units2);

        assertEq(fcStorage.lastPriceFeedUpdate(), block.timestamp);
        assertEq(fcStorage.ethUsdPrice(), uint256(newEthUsdPrice));
    }

    function testFuzzRentRevertsAfterDeadline(address msgSender, uint256 id, uint256 units) public {
        vm.warp(fcStorage.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        vm.prank(msgSender);
        fcStorage.rent(id, units);
    }

    function testFuzzRentRevertsInsufficientPayment(
        address msgSender,
        uint256 id,
        uint256 units,
        uint256 delta
    ) public {
        units = bound(units, 1, fcStorage.maxUnits());
        uint256 price = fcStorage.price(units);
        uint256 value = price - bound(delta, 1, price);
        vm.deal(msgSender, value);

        vm.expectRevert(StorageRent.InvalidPayment.selector);
        vm.prank(msgSender);
        fcStorage.rent{value: value}(id, units);
    }

    function testFuzzRentRevertsExcessPayment(address msgSender, uint256 id, uint256 units, uint256 delta) public {
        // Buy between 1 and maxUnits units.
        units = bound(units, 1, fcStorage.maxUnits());

        // Add a fuzzed amount to the price.
        uint256 price = fcStorage.price(units);
        uint256 value = price + bound(delta, 1, type(uint256).max - price);
        vm.deal(msgSender, value);

        vm.expectRevert(StorageRent.InvalidPayment.selector);
        vm.prank(msgSender);
        fcStorage.rent{value: value}(id, units);
    }

    function testFuzzRentRevertsExceedsCapacity(address msgSender, uint256 id, uint256 units) public {
        // Buy all the available units.
        uint256 maxUnits = fcStorage.maxUnits();
        uint256 maxUnitsPrice = fcStorage.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        fcStorage.rent{value: maxUnitsPrice}(0, maxUnits);

        // Attempt to buy a fuzzed amount units.
        units = bound(units, 1, fcStorage.maxUnits());
        uint256 price = fcStorage.unitPrice() * units;
        vm.deal(msgSender, price);

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        vm.prank(msgSender);
        fcStorage.rent{value: price}(id, units);
    }

    function testFuzzInitialPrice(uint128 quantity) public {
        assertEq(fcStorage.price(quantity), INITIAL_PRICE_IN_ETH * quantity);
    }

    function testInitialUnitPrice() public {
        assertEq(fcStorage.unitPrice(), INITIAL_PRICE_IN_ETH);
    }

    function testFuzzBatchRent(address msgSender, uint256[] calldata _ids, uint16[] calldata _units) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);

        // Fuzzed dynamic arrays have a fuzzed length up to 256 elements.
        // Truncate the longer one so their lengths match.
        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }
        batchRentStorage(msgSender, ids, units);
    }

    function testFuzzBatchRentCachedPrice(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units,
        int256 newEthUsdPrice,
        uint256 warp
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);

        uint256 lastPriceFeedUpdate = fcStorage.lastPriceFeedUpdate();
        uint256 ethUsdPrice = fcStorage.ethUsdPrice();

        // Fuzzed dynamic arrays have a fuzzed length up to 256 elements.
        // Truncate the longer one so their lengths match.
        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }
        batchRentStorage(msgSender, ids, units);

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        warp = bound(warp, 0, fcStorage.priceFeedCacheDuration());
        vm.warp(block.timestamp + warp);

        batchRentStorage(msgSender, ids, units);

        assertEq(fcStorage.lastPriceFeedUpdate(), lastPriceFeedUpdate);
        assertEq(fcStorage.ethUsdPrice(), ethUsdPrice);
    }

    function testFuzzBatchRentPriceRefresh(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units,
        int256 newEthUsdPrice
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);

        // Fuzzed dynamic arrays have a fuzzed length up to 256 elements.
        // Truncate the longer one so their lengths match.
        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }
        batchRentStorage(msgSender, ids, units);

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        vm.warp(block.timestamp + fcStorage.priceFeedCacheDuration() + 1);

        batchRentStorage(msgSender, ids, units);

        assertEq(fcStorage.lastPriceFeedUpdate(), block.timestamp);
        assertEq(fcStorage.ethUsdPrice(), uint256(newEthUsdPrice));
    }

    function testFuzzBatchRentRevertsAfterDeadline(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);
        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }
        vm.warp(fcStorage.deprecationTimestamp() + 1);
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }
        uint256 totalCost = fcStorage.price(totalUnits);
        vm.assume(totalUnits <= fcStorage.maxUnits() - fcStorage.rentedUnits());
        vm.deal(msgSender, totalCost);
        vm.prank(msgSender);
        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        fcStorage.batchRent{value: totalCost}(ids, units);
    }

    function testFuzzBatchRentRevertsEmptyArray(
        address msgSender,
        uint256[] memory ids,
        uint256[] memory units,
        bool emptyIds
    ) public {
        // Switch on emptyIds and set one array to length zero.
        if (emptyIds) {
            ids = new uint256[](0);
        } else {
            units = new uint256[](0);
        }

        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidBatchInput.selector);
        fcStorage.batchRent{value: 0}(ids, units);
    }

    function testFuzzBatchRentRevertsMismatchedArrayLength(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);

        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }

        // Add an extra element to the units array
        uint256[] memory units = new uint256[](length + 1);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }

        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }
        uint256 totalCost = fcStorage.price(totalUnits);
        vm.assume(totalUnits <= fcStorage.maxUnits() - fcStorage.rentedUnits());
        vm.deal(msgSender, totalCost);

        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidBatchInput.selector);
        fcStorage.batchRent{value: totalCost}(ids, units);
    }

    function testFuzzBatchRentRevertsInsufficientPayment(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units,
        uint256 delta
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);
        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }

        // Calculate the number of total units purchased
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }

        // Throw away the run if the total units is zero
        vm.assume(totalUnits > 0);

        // Throw away runs where the total units exceed max capacity
        uint256 totalCost = fcStorage.price(totalUnits);
        uint256 value = totalCost - bound(delta, 1, totalCost);
        vm.assume(totalUnits <= fcStorage.maxUnits() - fcStorage.rentedUnits());
        vm.deal(msgSender, totalCost);

        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidPayment.selector);
        fcStorage.batchRent{value: value}(ids, units);
    }

    function testFuzzBatchRentRevertsExcessPayment(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units,
        uint256 delta
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);
        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }

        // Calculate the number of total units purchased
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }

        // Throw away the run if the total units is zero or exceed max capacity
        vm.assume(totalUnits > 0);
        vm.assume(totalUnits <= fcStorage.maxUnits() - fcStorage.rentedUnits());

        // Add an extra fuzzed amount to the required payment
        uint256 totalCost = fcStorage.price(totalUnits);
        uint256 value = totalCost + bound(delta, 1, type(uint256).max - totalCost);

        vm.deal(msgSender, value);
        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidPayment.selector);
        fcStorage.batchRent{value: value}(ids, units);
    }

    function testFuzzBatchRentRevertsExceedsCapacity(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        fcStorage.setMaxUnits(uint256(256) * type(uint16).max);
        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256 totalUnits;
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
            totalUnits += units[i];
        }
        vm.assume(totalUnits > 0);

        // Buy all the available units.
        uint256 maxUnits = fcStorage.maxUnits();
        uint256 maxUnitsPrice = fcStorage.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        fcStorage.rent{value: maxUnitsPrice}(0, maxUnits);

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        vm.prank(msgSender);
        fcStorage.batchRent(ids, units);
    }

    function testFuzzUnitPriceRefresh(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        priceFeed.setPrice(ethUsdPrice);
        fcStorage.refreshPrice();
        fcStorage.setPrice(usdUnitPrice);

        assertEq(fcStorage.unitPrice(), (uint256(usdUnitPrice)).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzUnitPriceCached(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = fcStorage.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);
        fcStorage.setPrice(usdUnitPrice);

        assertEq(fcStorage.unitPrice(), uint256(usdUnitPrice) * 1e18 / cachedPrice);
    }

    function testPriceRoundsUp() public {
        priceFeed.setPrice(1e18 + 1);
        fcStorage.refreshPrice();
        fcStorage.setPrice(1);

        assertEq(fcStorage.price(1), 1);
    }

    function testFuzzPrice(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        priceFeed.setPrice(ethUsdPrice);
        fcStorage.refreshPrice();
        fcStorage.setPrice(usdUnitPrice);

        assertEq(fcStorage.price(units), (uint256(usdUnitPrice) * units).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzPriceCached(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = fcStorage.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);
        fcStorage.setPrice(usdUnitPrice);

        assertEq(fcStorage.price(units), (uint256(usdUnitPrice) * units).divWadUp(cachedPrice));
    }

    function testFuzzPriceFeedRevertsInvalidPrice(int256 price) public {
        // Ensure price is zero or negative
        price = price > 0 ? -price : price;
        priceFeed.setPrice(price);

        vm.expectRevert(StorageRent.InvalidPrice.selector);
        fcStorage.refreshPrice();
    }

    function testPriceFeedRevertsStaleAnswer() public {
        // Set stale answeredInRound value
        priceFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 2,
                answer: 2000e8,
                startedAt: block.timestamp,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(StorageRent.StaleAnswer.selector);
        fcStorage.refreshPrice();
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
        vm.expectRevert(StorageRent.IncompleteRound.selector);
        fcStorage.refreshPrice();
    }

    function testUptimeFeedRevertsSequencerDown(int256 answer) public {
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

        vm.expectRevert(StorageRent.SequencerDown.selector);
        fcStorage.refreshPrice();
    }

    function testUptimeFeedRevertsStaleAnswer() public {
        // Set stale answeredInRound value
        uptimeFeed.setRoundData(
            MockChainlinkFeed.RoundData({
                roundId: 2,
                answer: 0,
                startedAt: block.timestamp,
                timeStamp: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.expectRevert(StorageRent.StaleAnswer.selector);
        fcStorage.refreshPrice();
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
        vm.expectRevert(StorageRent.IncompleteRound.selector);
        fcStorage.refreshPrice();
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

        vm.expectRevert(StorageRent.GracePeriodNotOver.selector);
        fcStorage.refreshPrice();
    }

    function testOnlyOwnerCanRefreshPrice() public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.refreshPrice();
    }

    function testFuzzOnlyOwnerCanCredit(uint256 fid, uint256 units) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.credit(fid, units);
    }

    function testFuzzCredit(uint256 fid, uint32 units) public {
        credit(address(this), fid, units);
    }

    function testFuzzCreditRevertsExceedsCapacity(uint256 fid, uint32 units) public {
        // Buy all the available units.
        uint256 maxUnits = fcStorage.maxUnits();
        uint256 maxUnitsPrice = fcStorage.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        fcStorage.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        fcStorage.credit(fid, units);
    }

    function testFuzzCreditRevertsAfterDeadline(uint256 fid, uint32 units) public {
        vm.warp(fcStorage.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        fcStorage.credit(fid, units);
    }

    function testFuzzCreditRevertsZeroUnits(uint256 fid) public {
        vm.expectRevert(StorageRent.InvalidAmount.selector);
        fcStorage.credit(fid, 0);
    }

    function testFuzzOnlyOwnerCanBatchCredit(uint256[] calldata fids, uint256 units) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.batchCredit(fids, units);
    }

    function testFuzzBatchCredit(uint256[] calldata fids, uint32 units) public {
        batchCredit(fids, units);
    }

    function testFuzzBatchCreditRevertsExceedsCapacity(uint256[] calldata fids, uint32 units) public {
        vm.assume(fids.length > 0);

        // Buy all the available units.
        uint256 maxUnits = fcStorage.maxUnits();
        uint256 maxUnitsPrice = fcStorage.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        fcStorage.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        fcStorage.batchCredit(fids, units);
    }

    function testFuzzBatchCreditRevertsAfterDeadline(uint256[] calldata fids, uint32 units) public {
        vm.warp(fcStorage.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        fcStorage.batchCredit(fids, units);
    }

    function testFuzzOnlyOwnerCanSetUSDUnitPrice(uint256 unitPrice) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.setPrice(unitPrice);
    }

    function testFuzzSetUSDUnitPrice(uint256 unitPrice) public {
        uint256 currentPrice = fcStorage.usdUnitPrice();

        vm.expectEmit(false, false, false, true);
        emit SetPrice(currentPrice, unitPrice);

        fcStorage.setPrice(unitPrice);

        assertEq(fcStorage.usdUnitPrice(), unitPrice);
    }

    function testFuzzOnlyOwnerCanSetMaxUnits(uint256 maxUnits) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.setMaxUnits(maxUnits);
    }

    function testFuzzSetMaxUnitsEmitsEvent(uint256 maxUnits) public {
        uint256 currentMax = fcStorage.maxUnits();

        vm.expectEmit(false, false, false, true);
        emit SetMaxUnits(currentMax, maxUnits);

        fcStorage.setMaxUnits(maxUnits);

        assertEq(fcStorage.maxUnits(), maxUnits);
    }

    function testFuzzOnlyOwnerCanSetDeprecationTime(uint256 timestamp) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.setDeprecationTimestamp(timestamp);
    }

    function testFuzzSetDeprecationTime(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, type(uint256).max);
        uint256 currentEnd = fcStorage.deprecationTimestamp();

        vm.expectEmit(false, false, false, true);
        emit SetDeprecationTimestamp(currentEnd, timestamp);

        fcStorage.setDeprecationTimestamp(timestamp);

        assertEq(fcStorage.deprecationTimestamp(), timestamp);
    }

    function testFuzzSetDeprecationTimeRevertsInPast() public {
        vm.expectRevert(StorageRent.InvalidDeprecationTimestamp.selector);
        fcStorage.setDeprecationTimestamp(block.timestamp - 1);
    }

    function testFuzzOnlyOwnerCanSetCacheDuration(uint256 duration) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.setCacheDuration(duration);
    }

    function testFuzzSetCacheDuration(uint256 duration) public {
        uint256 currentDuration = fcStorage.priceFeedCacheDuration();

        vm.expectEmit(false, false, false, true);
        emit SetCacheDuration(currentDuration, duration);

        fcStorage.setCacheDuration(duration);

        assertEq(fcStorage.priceFeedCacheDuration(), duration);
    }

    function testFuzzOnlyOwnerCanSetGracePeriod(uint256 duration) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.setGracePeriod(duration);
    }

    function testFuzzSetGracePeriod(uint256 duration) public {
        uint256 currentGracePeriod = fcStorage.uptimeFeedGracePeriod();

        vm.expectEmit(false, false, false, true);
        emit SetGracePeriod(currentGracePeriod, duration);

        fcStorage.setGracePeriod(duration);

        assertEq(fcStorage.uptimeFeedGracePeriod(), duration);
    }

    function testFuzzWithdrawal(address msgSender, uint256 id, uint200 units, uint256 amount) public {
        uint256 balanceBefore = address(owner).balance;

        rentStorage(msgSender, id, units);

        // Don't withdraw more than the contract balance
        amount = bound(amount, 0, address(fcStorage).balance);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(owner, amount);

        vm.prank(owner);
        fcStorage.withdraw(owner, amount);

        uint256 balanceAfter = address(owner).balance;
        uint256 balanceChange = balanceAfter - balanceBefore;

        assertEq(balanceChange, amount);
    }

    function testFuzzWithdrawalRevertsInsufficientFunds(uint256 amount) public {
        // Ensure amount is positive
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(owner);
        vm.expectRevert(StorageRent.InsufficientFunds.selector);
        fcStorage.withdraw(owner, amount);
    }

    function testFuzzWithdrawalRevertsCallFailed() public {
        uint256 price = fcStorage.price(1);
        fcStorage.rent{value: price}(1, 1);

        vm.prank(owner);
        vm.expectRevert(StorageRent.CallFailed.selector);
        fcStorage.withdraw(address(revertOnReceive), price);
    }

    function testFuzzOnlyOwnerCanWithdraw(address to, uint256 amount) public {
        vm.prank(mallory);
        vm.expectRevert("Ownable: caller is not the owner");
        fcStorage.withdraw(to, amount);
    }

    function batchCredit(uint256[] memory ids, uint256 units) public {
        uint256 rented = fcStorage.rentedUnits();
        uint256 totalUnits = ids.length * units;
        vm.assume(totalUnits <= fcStorage.maxUnits() - fcStorage.rentedUnits());

        // Expect emitted events
        for (uint256 i; i < ids.length; ++i) {
            vm.expectEmit(true, true, false, true);
            emit Rent(owner, ids[i], units);
        }
        fcStorage.batchCredit(ids, units);

        // Expect rented units to increase
        assertEq(fcStorage.rentedUnits(), rented + totalUnits);
    }

    function batchRentStorage(
        address msgSender,
        uint256[] memory ids,
        uint256[] memory units
    ) public returns (uint256) {
        uint256 rented = fcStorage.rentedUnits();
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }
        uint256 totalCost = fcStorage.price(totalUnits);
        vm.deal(msgSender, totalCost);
        vm.assume(totalUnits <= fcStorage.maxUnits() - fcStorage.rentedUnits());

        // Expect emitted events
        for (uint256 i; i < ids.length; ++i) {
            if (units[i] != 0) {
                vm.expectEmit(true, true, false, true);
                emit Rent(msgSender, ids[i], units[i]);
            }
        }
        vm.prank(msgSender);
        fcStorage.batchRent{value: totalCost}(ids, units);

        // Expect rented units to increase
        assertEq(fcStorage.rentedUnits(), rented + totalUnits);
        return totalCost;
    }

    function credit(address msgSender, uint256 id, uint256 units) public {
        uint256 rented = fcStorage.rentedUnits();
        uint256 remaining = fcStorage.maxUnits() - rented;
        vm.assume(remaining > 0);
        units = bound(units, 1, remaining);

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(msgSender, id, units);

        vm.prank(msgSender);
        fcStorage.credit(id, units);

        // Expect rented units to increase
        assertEq(fcStorage.rentedUnits(), rented + units);
    }

    function rentStorage(address msgSender, uint256 id, uint256 units) public returns (uint256) {
        uint256 rented = fcStorage.rentedUnits();
        uint256 remaining = fcStorage.maxUnits() - rented;
        vm.assume(remaining > 0);
        units = bound(units, 1, remaining);
        uint256 price = fcStorage.price(units);
        vm.deal(msgSender, price);

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(msgSender, id, units);

        vm.prank(msgSender);
        fcStorage.rent{value: price}(id, units);

        // Expect rented units to increase
        assertEq(fcStorage.rentedUnits(), rented + units);
        return price;
    }

    /* solhint-disable-next-line no-empty-blocks */
    receive() external payable {}
}
