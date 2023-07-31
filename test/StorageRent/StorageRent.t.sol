// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {StorageRent} from "../../src/StorageRent.sol";
import {TransferHelper} from "../../src/lib/TransferHelper.sol";
import {StorageRentTestSuite, StorageRentHarness} from "./StorageRentTestSuite.sol";
import {MockChainlinkFeed} from "../Utils.sol";

/* solhint-disable state-visibility */

contract StorageRentTest is StorageRentTestSuite {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Rent(address indexed buyer, uint256 indexed id, uint256 units);
    event SetPrice(uint256 oldPrice, uint256 newPrice);
    event SetFixedEthUsdPrice(uint256 oldPrice, uint256 newPrice);
    event SetMaxUnits(uint256 oldMax, uint256 newMax);
    event SetDeprecationTimestamp(uint256 oldTimestamp, uint256 newTimestamp);
    event SetCacheDuration(uint256 oldDuration, uint256 newDuration);
    event SetMaxAge(uint256 oldAge, uint256 newAge);
    event SetGracePeriod(uint256 oldPeriod, uint256 newPeriod);
    event SetVault(address oldVault, address newVault);
    event Withdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZED VALUES
    //////////////////////////////////////////////////////////////*/

    function testVersion() public {
        assertEq(storageRent.VERSION(), "2023.07.12");
    }

    function testRoles() public {
        assertEq(storageRent.adminRoleId(), keccak256("ADMIN_ROLE"));
        assertEq(storageRent.operatorRoleId(), keccak256("OPERATOR_ROLE"));
        assertEq(storageRent.treasurerRoleId(), keccak256("TREASURER_ROLE"));
    }

    function testDefaultAdmin() public {
        assertTrue(storageRent.hasRole(storageRent.DEFAULT_ADMIN_ROLE(), roleAdmin));
    }

    function testPriceFeedDefault() public {
        assertEq(address(storageRent.priceFeed()), address(priceFeed));
    }

    function testUptimeFeedDefault() public {
        assertEq(address(storageRent.uptimeFeed()), address(uptimeFeed));
    }

    function testDeprecationTimestampDefault() public {
        assertEq(storageRent.deprecationTimestamp(), DEPLOYED_AT + INITIAL_RENTAL_PERIOD);
    }

    function testUsdUnitPriceDefault() public {
        assertEq(storageRent.usdUnitPrice(), INITIAL_USD_UNIT_PRICE);
    }

    function testMaxUnitsDefault() public {
        assertEq(storageRent.maxUnits(), INITIAL_MAX_UNITS);
    }

    function testRentedUnitsDefault() public {
        assertEq(storageRent.rentedUnits(), 0);
    }

    function testEthUSDPriceDefault() public {
        assertEq(storageRent.ethUsdPrice(), uint256(ETH_USD_PRICE));
    }

    function testPrevEthUSDPriceDefault() public {
        assertEq(storageRent.prevEthUsdPrice(), uint256(ETH_USD_PRICE));
    }

    function testLastPriceFeedUpdateDefault() public {
        assertEq(storageRent.lastPriceFeedUpdateTime(), block.timestamp);
    }

    function testLastPriceFeedUpdateBlockDefault() public {
        assertEq(storageRent.lastPriceFeedUpdateBlock(), block.number);
    }

    function testPriceFeedCacheDurationDefault() public {
        assertEq(storageRent.priceFeedCacheDuration(), INITIAL_PRICE_FEED_CACHE_DURATION);
    }

    function testPriceFeedMaxAgeDefault() public {
        assertEq(storageRent.priceFeedMaxAge(), INITIAL_PRICE_FEED_MAX_AGE);
    }

    function testUptimeFeedGracePeriodDefault() public {
        assertEq(storageRent.uptimeFeedGracePeriod(), INITIAL_UPTIME_FEED_GRACE_PERIOD);
    }

    function testFuzzInitialPrice(uint128 quantity) public {
        assertEq(storageRent.price(quantity), INITIAL_PRICE_IN_ETH * quantity);
    }

    function testInitialUnitPrice() public {
        assertEq(storageRent.unitPrice(), INITIAL_PRICE_IN_ETH);
    }

    function testInitialPriceUpdate() public {
        // Clear ethUsdPrice storage slot
        vm.store(address(storageRent), bytes32(uint256(11)), bytes32(0));
        assertEq(storageRent.ethUsdPrice(), 0);

        // Clear prevEthUsdPrice storage slot
        vm.store(address(storageRent), bytes32(uint256(12)), bytes32(0));
        assertEq(storageRent.prevEthUsdPrice(), 0);

        vm.prank(admin);
        storageRent.refreshPrice();

        assertEq(storageRent.ethUsdPrice(), uint256(ETH_USD_PRICE));
        assertEq(storageRent.prevEthUsdPrice(), uint256(ETH_USD_PRICE));
        assertEq(storageRent.ethUsdPrice(), storageRent.prevEthUsdPrice());
    }

    /*//////////////////////////////////////////////////////////////
                                  RENT
    //////////////////////////////////////////////////////////////*/

    function testFuzzRent(address msgSender, uint256 id, uint200 units) public {
        rentStorage(msgSender, id, units);
    }

    function testFuzzRentRevertsZeroUnits(address msgSender, uint256 id) public {
        vm.deal(msgSender, storageRent.price(100));

        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidAmount.selector);
        storageRent.rent(id, 0);
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
        _assumeClean(msgSender1);
        _assumeClean(msgSender2);
        uint256 lastPriceFeedUpdateTime = storageRent.lastPriceFeedUpdateTime();
        uint256 lastPriceFeedUpdateBlock = storageRent.lastPriceFeedUpdateBlock();
        uint256 ethUsdPrice = storageRent.ethUsdPrice();
        uint256 prevEthUsdPrice = storageRent.prevEthUsdPrice();

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        rentStorage(msgSender1, id1, units1);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        warp = bound(warp, 0, storageRent.priceFeedCacheDuration());
        vm.warp(block.timestamp + warp);

        rentStorage(msgSender2, id2, units2);

        assertEq(storageRent.lastPriceFeedUpdateTime(), lastPriceFeedUpdateTime);
        assertEq(storageRent.lastPriceFeedUpdateBlock(), lastPriceFeedUpdateBlock);
        assertEq(storageRent.ethUsdPrice(), ethUsdPrice);
        assertEq(storageRent.prevEthUsdPrice(), prevEthUsdPrice);
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
        _assumeClean(msgSender1);
        _assumeClean(msgSender2);
        uint256 ethUsdPrice = storageRent.ethUsdPrice();

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        rentStorage(msgSender1, id1, units1);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        vm.warp(block.timestamp + storageRent.priceFeedCacheDuration() + 1);

        uint256 expectedPrice = storageRent.unitPrice();

        (, uint256 unitPrice,,) = rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice, expectedPrice);
        assertEq(storageRent.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRent.lastPriceFeedUpdateBlock(), block.number);
        assertEq(storageRent.prevEthUsdPrice(), ethUsdPrice);
        assertEq(storageRent.ethUsdPrice(), uint256(newEthUsdPrice));
    }

    function testFuzzRentIntraBlockPriceDecrease(
        address msgSender1,
        uint256 id1,
        uint200 units1,
        address msgSender2,
        uint256 id2,
        uint200 units2,
        uint256 decrease
    ) public {
        _assumeClean(msgSender1);
        _assumeClean(msgSender2);
        uint256 ethUsdPrice = storageRent.ethUsdPrice();

        decrease = bound(decrease, 1, ethUsdPrice);
        uint256 newEthUsdPrice = ethUsdPrice - decrease;
        vm.assume(newEthUsdPrice > 0);

        // Set a new ETH/USD price
        priceFeed.setPrice(int256(newEthUsdPrice));

        vm.warp(block.timestamp + storageRent.priceFeedCacheDuration() + 1);

        (, uint256 unitPrice1,, uint256 unitPricePaid1) = rentStorage(msgSender1, id1, units1);
        (, uint256 unitPrice2,, uint256 unitPricePaid2) = rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice1, unitPrice2);
        assertEq(unitPricePaid1, unitPricePaid2);
        assertEq(unitPricePaid1, unitPrice1);
        assertEq(storageRent.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRent.lastPriceFeedUpdateBlock(), block.number);
        assertEq(storageRent.prevEthUsdPrice(), ethUsdPrice);
        assertEq(storageRent.ethUsdPrice(), newEthUsdPrice);
    }

    function testFuzzRentIntraBlockPriceIncrease(
        address msgSender1,
        uint256 id1,
        uint200 units1,
        address msgSender2,
        uint256 id2,
        uint200 units2,
        uint256 increase
    ) public {
        _assumeClean(msgSender1);
        _assumeClean(msgSender2);
        uint256 ethUsdPrice = storageRent.ethUsdPrice();

        increase = bound(increase, 1, uint256(type(int256).max) - ethUsdPrice);
        uint256 newEthUsdPrice = ethUsdPrice + increase;

        // Set a new ETH/USD price
        priceFeed.setPrice(int256(newEthUsdPrice));

        vm.warp(block.timestamp + storageRent.priceFeedCacheDuration() + 1);

        (, uint256 unitPrice1,, uint256 unitPricePaid1) = rentStorage(msgSender1, id1, units1);
        (, uint256 unitPrice2,, uint256 unitPricePaid2) = rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice1, unitPrice2);
        assertEq(unitPricePaid1, unitPricePaid2);
        assertEq(unitPricePaid1, unitPrice1);
        assertEq(storageRent.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRent.lastPriceFeedUpdateBlock(), block.number);
        assertEq(storageRent.prevEthUsdPrice(), ethUsdPrice);
        assertEq(storageRent.ethUsdPrice(), newEthUsdPrice);
    }

    function testFuzzRentFixedPrice(
        address msgSender1,
        uint256 id1,
        uint200 units1,
        address msgSender2,
        uint256 id2,
        uint200 units2,
        int256 newEthUsdPrice,
        uint256 fixedPrice
    ) public {
        uint256 lastPriceFeedUpdateTime = storageRent.lastPriceFeedUpdateTime();
        uint256 lastPriceFeedUpdateBlock = storageRent.lastPriceFeedUpdateBlock();
        uint256 prevEthUsdPrice = storageRent.prevEthUsdPrice();
        uint256 ethUsdPrice = storageRent.ethUsdPrice();

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);
        fixedPrice = bound(fixedPrice, 10e8, 100_000e8);

        rentStorage(msgSender1, id1, units1);

        // Update the Chainlink price and fake a failure
        priceFeed.setPrice(newEthUsdPrice);
        priceFeed.setShouldRevert(true);

        // Set a fixed ETH/USD price, disabling price feeds
        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(fixedPrice);

        vm.warp(block.timestamp + storageRent.priceFeedCacheDuration() + 1);

        uint256 expectedPrice = storageRent.unitPrice();

        // Rent succeeds even though price feed is reverting
        (, uint256 unitPrice,,) = rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice, expectedPrice);

        // Price feed parameters do not change, since it's not refreshed
        assertEq(storageRent.lastPriceFeedUpdateTime(), lastPriceFeedUpdateTime);
        assertEq(storageRent.lastPriceFeedUpdateBlock(), lastPriceFeedUpdateBlock);
        assertEq(storageRent.prevEthUsdPrice(), prevEthUsdPrice);
        assertEq(storageRent.ethUsdPrice(), ethUsdPrice);
    }

    function testFuzzRentRevertsAfterDeadline(address msgSender, uint256 id, uint256 units) public {
        units = bound(units, 1, storageRent.maxUnits());
        uint256 price = storageRent.price(units);
        vm.deal(msgSender, price);

        vm.warp(storageRent.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        vm.prank(msgSender);
        storageRent.rent(id, units);
    }

    function testFuzzRentRevertsInsufficientPayment(
        address msgSender,
        uint256 id,
        uint256 units,
        uint256 delta
    ) public {
        units = bound(units, 1, storageRent.maxUnits());
        uint256 price = storageRent.price(units);
        uint256 value = price - bound(delta, 1, price);
        vm.deal(msgSender, value);

        vm.expectRevert(StorageRent.InvalidPayment.selector);
        vm.prank(msgSender);
        storageRent.rent{value: value}(id, units);
    }

    function testFuzzRentRefundsExcessPayment(uint256 id, uint256 units, uint256 delta) public {
        // Buy between 1 and maxUnits units.
        units = bound(units, 1, storageRent.maxUnits());

        // Ensure there are units remaining
        uint256 rented = storageRent.rentedUnits();
        uint256 remaining = storageRent.maxUnits() - rented;
        vm.assume(remaining > 0);

        units = bound(units, 1, remaining);
        // Add a fuzzed amount to the price.
        uint256 price = storageRent.price(units);
        uint256 extra = bound(delta, 1, type(uint256).max - price);
        vm.deal(address(this), price + extra);

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(address(this), id, units);

        storageRent.rent{value: price + extra}(id, units);

        assertEq(address(this).balance, extra);
    }

    function testFuzzRentFailedRefundRevertsCallFailed(uint256 id, uint256 units, uint256 delta) public {
        // Buy between 1 and maxUnits units.
        units = bound(units, 1, storageRent.maxUnits());

        // Ensure there are units remaining
        uint256 rented = storageRent.rentedUnits();
        uint256 remaining = storageRent.maxUnits() - rented;
        vm.assume(remaining > 0);

        units = bound(units, 1, remaining);
        // Add a fuzzed amount to the price.
        uint256 price = storageRent.price(units);
        uint256 extra = bound(delta, 1, type(uint256).max - price);
        vm.deal(address(revertOnReceive), price + extra);

        vm.prank(address(revertOnReceive));
        vm.expectRevert(TransferHelper.CallFailed.selector);
        storageRent.rent{value: price + extra}(id, units);
    }

    function testFuzzRentRevertsExceedsCapacity(address msgSender, uint256 id, uint256 units) public {
        // Buy all the available units.
        uint256 maxUnits = storageRent.maxUnits();
        uint256 maxUnitsPrice = storageRent.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRent.rent{value: maxUnitsPrice}(0, maxUnits);

        // Attempt to buy a fuzzed amount units.
        units = bound(units, 1, storageRent.maxUnits());
        uint256 price = storageRent.unitPrice() * units;
        vm.deal(msgSender, price);

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        vm.prank(msgSender);
        storageRent.rent{value: price}(id, units);
    }

    /*//////////////////////////////////////////////////////////////
                               BATCH RENT
    //////////////////////////////////////////////////////////////*/

    function testFuzzBatchRent(address msgSender, uint256[] calldata _ids, uint16[] calldata _units) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

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
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

        uint256 lastPriceFeedUpdate = storageRent.lastPriceFeedUpdateTime();
        uint256 ethUsdPrice = storageRent.ethUsdPrice();

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

        warp = bound(warp, 0, storageRent.priceFeedCacheDuration());
        vm.warp(block.timestamp + warp);

        batchRentStorage(msgSender, ids, units);

        assertEq(storageRent.lastPriceFeedUpdateTime(), lastPriceFeedUpdate);
        assertEq(storageRent.ethUsdPrice(), ethUsdPrice);
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
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

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

        vm.warp(block.timestamp + storageRent.priceFeedCacheDuration() + 1);

        batchRentStorage(msgSender, ids, units);

        assertEq(storageRent.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRent.ethUsdPrice(), uint256(newEthUsdPrice));
    }

    function testFuzzBatchRentRevertsAfterDeadline(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

        uint256 length = _ids.length <= _units.length ? _ids.length : _units.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ids[i] = _ids[i];
        }
        uint256[] memory units = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            units[i] = _units[i];
        }
        vm.warp(storageRent.deprecationTimestamp() + 1);
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }
        uint256 totalCost = storageRent.price(totalUnits);
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());
        vm.deal(msgSender, totalCost);
        vm.prank(msgSender);
        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        storageRent.batchRent{value: totalCost}(ids, units);
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
        storageRent.batchRent{value: 0}(ids, units);
    }

    function testFuzzBatchRentRevertsMismatchedArrayLength(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

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
        uint256 totalCost = storageRent.price(totalUnits);
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());
        vm.deal(msgSender, totalCost);

        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidBatchInput.selector);
        storageRent.batchRent{value: totalCost}(ids, units);
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
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

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
        uint256 totalCost = storageRent.price(totalUnits);
        uint256 value = totalCost - bound(delta, 1, totalCost);
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());
        vm.deal(msgSender, totalCost);

        vm.prank(msgSender);
        vm.expectRevert(StorageRent.InvalidPayment.selector);
        storageRent.batchRent{value: value}(ids, units);
    }

    function testFuzzBatchRentRefundsExcessPayment(
        uint256[] calldata _ids,
        uint16[] calldata _units,
        uint256 delta
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

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
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());

        // Add an extra fuzzed amount to the required payment
        uint256 totalCost = storageRent.price(totalUnits);
        uint256 extra = bound(delta, 1, type(uint256).max - totalCost);
        uint256 value = totalCost + extra;

        vm.deal(address(this), value);
        storageRent.batchRent{value: value}(ids, units);

        assertEq(address(this).balance, extra);
    }

    function testFuzzBatchRentFailedRefundRevertsCallFailed(
        uint256[] calldata _ids,
        uint16[] calldata _units,
        uint256 delta
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        vm.startPrank(admin);
        storageRent.setMaxUnits(type(uint256).max);
        vm.stopPrank();

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
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());

        // Add an extra fuzzed amount to the required payment
        uint256 totalCost = storageRent.price(totalUnits);
        uint256 extra = bound(delta, 1, type(uint256).max - totalCost);
        uint256 value = totalCost + extra;

        vm.deal(address(revertOnReceive), value);
        vm.prank(address(revertOnReceive));
        vm.expectRevert(TransferHelper.CallFailed.selector);
        storageRent.batchRent{value: value}(ids, units);
    }

    function testFuzzBatchRentRevertsExceedsCapacity(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set to a moderate max capacity to avoid overflow.
        vm.startPrank(admin);
        storageRent.setMaxUnits(10_000_000);
        vm.stopPrank();

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
        uint256 maxUnits = storageRent.maxUnits();
        uint256 maxUnitsPrice = storageRent.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRent.rent{value: maxUnitsPrice}(0, maxUnits);

        uint256 totalPrice = storageRent.price(totalUnits);
        vm.deal(msgSender, totalPrice);
        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        vm.prank(msgSender);
        storageRent.batchRent{value: totalPrice}(ids, units);
    }

    function testBatchRentCheckedMath() public {
        uint256[] memory fids = new uint256[](1);
        uint256[] memory units = new uint256[](1);
        units[0] = type(uint256).max;

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        storageRent.batchRent(fids, units);
    }

    /*//////////////////////////////////////////////////////////////
                               UNIT PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzUnitPriceRefresh(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        priceFeed.setPrice(ethUsdPrice);
        vm.startPrank(admin);
        storageRent.refreshPrice();
        storageRent.setPrice(usdUnitPrice);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(storageRent.unitPrice(), (uint256(usdUnitPrice)).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzUnitPriceCached(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = storageRent.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);

        vm.prank(admin);
        storageRent.setPrice(usdUnitPrice);

        assertEq(storageRent.unitPrice(), uint256(usdUnitPrice) * 1e18 / cachedPrice);
    }

    /*//////////////////////////////////////////////////////////////
                                  PRICE
    //////////////////////////////////////////////////////////////*/

    function testPriceRoundsUp() public {
        priceFeed.setPrice(1e18 + 1);

        vm.startPrank(admin);
        storageRent.refreshPrice();
        storageRent.setPrice(1);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(storageRent.price(1), 1);
    }

    function testFuzzPrice(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        priceFeed.setPrice(ethUsdPrice);
        vm.startPrank(admin);
        storageRent.refreshPrice();
        storageRent.setPrice(usdUnitPrice);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(storageRent.price(units), (uint256(usdUnitPrice) * units).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzPriceCached(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = storageRent.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);
        vm.prank(admin);
        storageRent.setPrice(usdUnitPrice);

        assertEq(storageRent.price(units), (uint256(usdUnitPrice) * units).divWadUp(cachedPrice));
    }

    /*//////////////////////////////////////////////////////////////
                               PRICE FEED
    //////////////////////////////////////////////////////////////*/

    function testFuzzPriceFeedRevertsInvalidPrice(int256 price) public {
        // Ensure price is zero or negative
        price = price > 0 ? -price : price;
        priceFeed.setPrice(price);

        vm.expectRevert(StorageRent.InvalidPrice.selector);
        vm.prank(admin);
        storageRent.refreshPrice();
    }

    function testPriceFeedRevertsStaleAnswerByRound() public {
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
        vm.prank(admin);
        storageRent.refreshPrice();
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

        vm.expectRevert(StorageRent.StaleAnswer.selector);
        vm.prank(admin);
        storageRent.refreshPrice();
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
        vm.expectRevert(StorageRent.IncompleteRound.selector);
        vm.prank(admin);
        storageRent.refreshPrice();
    }

    function testFuzzPriceFeedFailure(address msgSender, uint256 id, uint256 units) public {
        units = bound(units, 1, storageRent.maxUnits());
        uint256 price = storageRent.price(units);
        vm.deal(msgSender, price);

        // Fake a price feed error and ensure the next call will refresh the price.
        priceFeed.setShouldRevert(true);
        vm.warp(block.timestamp + storageRent.priceFeedCacheDuration() + 1);

        // Calling rent reverts.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(msgSender);
        storageRent.rent{value: price}(id, units);

        // Admin can set a failsafe fixed price.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, 4000e8);
        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(4000e8);

        // ETH doubled in USD terms, so we need
        // half as much for the same USD price.
        uint256 newPrice = storageRent.price(units);
        assertEq(newPrice, price / 2);

        // Calling rent now succeeds.
        vm.prank(msgSender);
        storageRent.rent{value: newPrice}(id, units);

        // Setting fixed price back to zero re-enables the price feed.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(4000e8, 0);
        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(0);

        // Calls revert again, since price feed is re-enabled.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(admin);
        storageRent.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                               UPTIME FEED
    //////////////////////////////////////////////////////////////*/

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
        vm.prank(admin);
        storageRent.refreshPrice();
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
        vm.prank(admin);
        storageRent.refreshPrice();
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
        vm.expectRevert(StorageRent.IncompleteRound.selector);
        vm.prank(admin);
        storageRent.refreshPrice();
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
        vm.prank(admin);
        storageRent.refreshPrice();
    }

    function testFuzzUptimeFeedFailure(address msgSender, uint256 id, uint256 units) public {
        units = bound(units, 1, storageRent.maxUnits());
        uint256 price = storageRent.price(units);
        vm.deal(msgSender, price);

        // Fake an uptime feed error and ensure the next call will refresh the price.
        uptimeFeed.setShouldRevert(true);
        vm.warp(block.timestamp + storageRent.priceFeedCacheDuration() + 1);

        // Calling rent reverts
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(msgSender);
        storageRent.rent{value: price}(id, units);

        // Admin can set a failsafe fixed price.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, 4000e8);
        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(4000e8);

        // ETH doubled in USD terms, so we need
        // half as much for the same USD price.
        uint256 newPrice = storageRent.price(units);
        assertEq(newPrice, price / 2);

        // Calling rent now succeeds.
        vm.prank(msgSender);
        storageRent.rent{value: newPrice}(id, units);

        // Setting fixed price back to zero re-enables the price feed.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(4000e8, 0);
        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(0);

        // Calls revert again, since price feed is re-enabled.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(admin);
        storageRent.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                              REFRESH PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAuthorizedCanRefreshPrice(address caller) public {
        vm.assume(caller != admin && caller != treasurer);

        vm.prank(caller);
        vm.expectRevert(StorageRent.Unauthorized.selector);
        storageRent.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                                 CREDIT
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOperatorCanCredit(address caller, uint256 fid, uint256 units) public {
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotOperator.selector);
        storageRent.credit(fid, units);
    }

    function testFuzzCredit(uint256 fid, uint32 units) public {
        credit(operator, fid, units);
    }

    function testFuzzCreditRevertsExceedsCapacity(uint256 fid, uint32 units) public {
        // Buy all the available units.
        uint256 maxUnits = storageRent.maxUnits();
        uint256 maxUnitsPrice = storageRent.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRent.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        vm.prank(operator);
        storageRent.credit(fid, units);
    }

    function testFuzzCreditRevertsAfterDeadline(uint256 fid, uint32 units) public {
        vm.warp(storageRent.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        vm.prank(operator);
        storageRent.credit(fid, units);
    }

    function testFuzzCreditRevertsZeroUnits(uint256 fid) public {
        vm.expectRevert(StorageRent.InvalidAmount.selector);
        vm.prank(operator);
        storageRent.credit(fid, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              BATCH CREDIT
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOperatorCanBatchCredit(address caller, uint256[] calldata fids, uint256 units) public {
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotOperator.selector);
        storageRent.batchCredit(fids, units);
    }

    function testFuzzBatchCredit(uint256[] calldata fids, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        batchCredit(fids, units);
    }

    function testFuzzBatchCreditRevertsZeroAmount(uint256[] calldata fids) public {
        vm.expectRevert(StorageRent.InvalidAmount.selector);
        vm.prank(operator);
        storageRent.batchCredit(fids, 0);
    }

    function testFuzzBatchCreditRevertsExceedsCapacity(uint256[] calldata fids, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        vm.assume(fids.length > 0);

        // Buy all the available units.
        uint256 maxUnits = storageRent.maxUnits();
        uint256 maxUnitsPrice = storageRent.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRent.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        vm.prank(operator);
        storageRent.batchCredit(fids, units);
    }

    function testFuzzBatchCreditRevertsAfterDeadline(uint256[] calldata fids, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        vm.warp(storageRent.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        vm.prank(operator);
        storageRent.batchCredit(fids, units);
    }

    /*//////////////////////////////////////////////////////////////
                            CONTINUOUS CREDIT
    //////////////////////////////////////////////////////////////*/

    function testOnlyOperatorCanContinuousCredit(address caller, uint16 start, uint256 n, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        uint256 end = uint256(start) + bound(n, 1, 10000);
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotOperator.selector);
        storageRent.continuousCredit(start, end, units);
    }

    function testContinuousCredit() public {
        // Simulate the initial seeding of the contract and check that events are emitted.
        continuousCredit(0, 20_000, 1, true);
    }

    function testFuzzContinuousCredit(uint16 start, uint256 n, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        uint256 end = uint256(start) + bound(n, 1, 1_000);
        // Avoid checking for events here since expectEmit can make the fuzzing
        // very slow, rely on testContinuousCredit to validate that instead.
        continuousCredit(start, end, units, false);
    }

    function testFuzzContinuousCreditRevertsZeroAmount(uint16 start, uint256 n) public {
        uint256 end = uint256(start) + bound(n, 1, 10000);

        vm.expectRevert(StorageRent.InvalidAmount.selector);
        vm.prank(operator);
        storageRent.continuousCredit(start, end, 0);
    }

    function testFuzzContinuousCreditRevertsExceedsCapacity(uint16 start, uint256 n, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        uint256 end = uint256(start) + bound(n, 1, 10000);

        // Buy all the available units.
        uint256 maxUnits = storageRent.maxUnits();
        uint256 maxUnitsPrice = storageRent.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRent.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRent.ExceedsCapacity.selector);
        vm.prank(operator);
        storageRent.continuousCredit(start, end, units);
    }

    function testFuzzContinuousCreditRevertsAfterDeadline(uint16 start, uint256 n, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        uint256 end = uint256(start) + bound(n, 0, 10000);
        vm.warp(storageRent.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRent.ContractDeprecated.selector);
        vm.prank(operator);
        storageRent.continuousCredit(start, end, units);
    }

    /*//////////////////////////////////////////////////////////////
                           SET USD UNIT PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminOrTreasurerCanSetUSDUnitPrice(address caller, uint256 unitPrice) public {
        vm.assume(caller != admin && caller != treasurer);

        vm.prank(caller);
        vm.expectRevert(StorageRent.Unauthorized.selector);
        storageRent.setPrice(unitPrice);
    }

    function testFuzzSetUSDUnitPrice(uint256 unitPrice) public {
        uint256 currentPrice = storageRent.usdUnitPrice();

        vm.expectEmit(false, false, false, true);
        emit SetPrice(currentPrice, unitPrice);

        vm.prank(admin);
        storageRent.setPrice(unitPrice);

        assertEq(storageRent.usdUnitPrice(), unitPrice);
    }

    /*//////////////////////////////////////////////////////////////
                           SET FIXED ETH PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetFixedEthUsdPrice(address caller, uint256 fixedPrice) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotAdmin.selector);
        storageRent.setFixedEthUsdPrice(fixedPrice);
    }

    function testFuzzSetFixedEthUsdPrice(uint256 fixedPrice) public {
        assertEq(storageRent.fixedEthUsdPrice(), 0);

        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, fixedPrice);

        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(fixedPrice);

        assertEq(storageRent.fixedEthUsdPrice(), fixedPrice);
    }

    function testFuzzSetFixedEthUsdPriceOverridesPriceFeed(uint256 fixedPrice) public {
        vm.assume(fixedPrice != storageRent.ethUsdPrice());
        fixedPrice = bound(fixedPrice, 1, type(uint256).max);

        uint256 usdUnitPrice = storageRent.usdUnitPrice();
        uint256 priceBefore = storageRent.unitPrice();

        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(fixedPrice);

        uint256 priceAfter = storageRent.unitPrice();

        assertTrue(priceBefore != priceAfter);
        assertEq(priceAfter, usdUnitPrice.divWadUp(fixedPrice));
    }

    function testFuzzRemoveFixedEthUsdPriceReenablesPriceFeed(uint256 fixedPrice) public {
        vm.assume(fixedPrice != storageRent.ethUsdPrice());
        fixedPrice = bound(fixedPrice, 1, type(uint256).max);

        uint256 usdUnitPrice = storageRent.usdUnitPrice();
        uint256 priceBefore = storageRent.unitPrice();

        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(fixedPrice);

        uint256 priceAfter = storageRent.unitPrice();

        assertTrue(priceBefore != priceAfter);
        assertEq(priceAfter, usdUnitPrice.divWadUp(fixedPrice));

        vm.prank(admin);
        storageRent.setFixedEthUsdPrice(0);
        assertEq(storageRent.fixedEthUsdPrice(), 0);

        uint256 priceFinal = storageRent.unitPrice();
        assertEq(priceBefore, priceFinal);
    }

    /*//////////////////////////////////////////////////////////////
                              SET MAX UNITS
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetMaxUnits(address caller, uint256 maxUnits) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotAdmin.selector);
        storageRent.setMaxUnits(maxUnits);
    }

    function testFuzzSetMaxUnitsEmitsEvent(uint256 maxUnits) public {
        uint256 currentMax = storageRent.maxUnits();

        vm.expectEmit(false, false, false, true);
        emit SetMaxUnits(currentMax, maxUnits);

        vm.prank(admin);
        storageRent.setMaxUnits(maxUnits);

        assertEq(storageRent.maxUnits(), maxUnits);
    }

    function testFuzzOnlyAdminCanSetDeprecationTime(address caller, uint256 timestamp) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotAdmin.selector);
        storageRent.setDeprecationTimestamp(timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        SET DEPRECATION TIMESTAMP
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetDeprecationTime(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, type(uint256).max);
        uint256 currentEnd = storageRent.deprecationTimestamp();

        vm.expectEmit(false, false, false, true);
        emit SetDeprecationTimestamp(currentEnd, timestamp);

        vm.prank(admin);
        storageRent.setDeprecationTimestamp(timestamp);

        assertEq(storageRent.deprecationTimestamp(), timestamp);
    }

    function testFuzzSetDeprecationTimeRevertsInPast() public {
        vm.expectRevert(StorageRent.InvalidDeprecationTimestamp.selector);
        vm.prank(admin);
        storageRent.setDeprecationTimestamp(block.timestamp - 1);
    }

    /*//////////////////////////////////////////////////////////////
                           SET CACHE DURATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetCacheDuration(address caller, uint256 duration) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotAdmin.selector);
        storageRent.setCacheDuration(duration);
    }

    function testFuzzSetCacheDuration(uint256 duration) public {
        uint256 currentDuration = storageRent.priceFeedCacheDuration();

        vm.expectEmit(false, false, false, true);
        emit SetCacheDuration(currentDuration, duration);

        vm.prank(admin);
        storageRent.setCacheDuration(duration);

        assertEq(storageRent.priceFeedCacheDuration(), duration);
    }

    /*//////////////////////////////////////////////////////////////
                           SET MAX PRICE AGE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetMaxAge(address caller, uint256 age) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotAdmin.selector);
        storageRent.setMaxAge(age);
    }

    function testFuzzSetMaxAge(uint256 age) public {
        uint256 currentAge = storageRent.priceFeedMaxAge();

        vm.expectEmit(false, false, false, true);
        emit SetMaxAge(currentAge, age);

        vm.prank(admin);
        storageRent.setMaxAge(age);

        assertEq(storageRent.priceFeedMaxAge(), age);
    }

    /*//////////////////////////////////////////////////////////////
                            SET GRACE PERIOD
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetGracePeriod(address caller, uint256 duration) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotAdmin.selector);
        storageRent.setGracePeriod(duration);
    }

    function testFuzzSetGracePeriod(uint256 duration) public {
        uint256 currentGracePeriod = storageRent.uptimeFeedGracePeriod();

        vm.expectEmit(false, false, false, true);
        emit SetGracePeriod(currentGracePeriod, duration);

        vm.prank(admin);
        storageRent.setGracePeriod(duration);

        assertEq(storageRent.uptimeFeedGracePeriod(), duration);
    }

    /*//////////////////////////////////////////////////////////////
                                SET VAULT
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetVault(address newVault) public {
        vm.assume(newVault != address(0));
        vm.expectEmit(false, false, false, true);
        emit SetVault(vault, newVault);

        vm.prank(admin);
        storageRent.setVault(newVault);

        assertEq(storageRent.vault(), newVault);
    }

    function testFuzzOnlyAdminCanSetVault(address caller, address vault) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotAdmin.selector);
        storageRent.setVault(vault);
    }

    function testSetVaultCannotBeZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(StorageRent.InvalidAddress.selector);
        storageRent.setVault(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function testFuzzWithdrawal(address msgSender, uint256 id, uint200 units, uint256 amount) public {
        uint256 balanceBefore = address(vault).balance;

        rentStorage(msgSender, id, units);

        // Don't withdraw more than the contract balance
        amount = bound(amount, 0, address(storageRent).balance);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(vault, amount);

        vm.prank(treasurer);
        storageRent.withdraw(amount);

        uint256 balanceAfter = address(vault).balance;
        uint256 balanceChange = balanceAfter - balanceBefore;

        assertEq(balanceChange, amount);
    }

    function testFuzzWithdrawalRevertsInsufficientFunds(uint256 amount) public {
        // Ensure amount is positive
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(treasurer);
        vm.expectRevert(TransferHelper.InsufficientFunds.selector);
        storageRent.withdraw(amount);
    }

    function testFuzzWithdrawalRevertsCallFailed() public {
        uint256 price = storageRent.price(1);
        storageRent.rent{value: price}(1, 1);

        vm.prank(admin);
        storageRent.setVault(address(revertOnReceive));

        vm.prank(treasurer);
        vm.expectRevert(TransferHelper.CallFailed.selector);
        storageRent.withdraw(price);
    }

    function testFuzzOnlyTreasurerCanWithdraw(address caller, uint256 amount) public {
        vm.assume(caller != treasurer);

        vm.prank(caller);
        vm.expectRevert(StorageRent.NotTreasurer.selector);
        storageRent.withdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function continuousCredit(uint256 start, uint256 end, uint256 units, bool assertEvents) public {
        uint256 rented = storageRent.rentedUnits();
        uint256 len = end - start;
        uint256 totalUnits = len * units;
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());

        if (assertEvents) {
            // Expect emitted events
            for (uint256 i; i < len; ++i) {
                vm.expectEmit(true, true, false, true);
                emit Rent(operator, start + i, units);
            }
        }

        vm.prank(operator);
        storageRent.continuousCredit(start, end, units);

        // Expect rented units to increase
        assertEq(storageRent.rentedUnits(), rented + totalUnits);
    }

    function batchCredit(uint256[] memory ids, uint256 units) public {
        uint256 rented = storageRent.rentedUnits();
        uint256 totalUnits = ids.length * units;
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());

        // Expect emitted events
        for (uint256 i; i < ids.length; ++i) {
            vm.expectEmit(true, true, false, true);
            emit Rent(operator, ids[i], units);
        }
        vm.prank(operator);
        storageRent.batchCredit(ids, units);

        // Expect rented units to increase
        assertEq(storageRent.rentedUnits(), rented + totalUnits);
    }

    function batchRentStorage(
        address msgSender,
        uint256[] memory ids,
        uint256[] memory units
    ) public returns (uint256) {
        uint256 rented = storageRent.rentedUnits();
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }
        uint256 totalCost = storageRent.price(totalUnits);
        vm.deal(msgSender, totalCost);
        vm.assume(totalUnits <= storageRent.maxUnits() - storageRent.rentedUnits());

        // Expect emitted events
        for (uint256 i; i < ids.length; ++i) {
            if (units[i] != 0) {
                vm.expectEmit(true, true, false, true);
                emit Rent(msgSender, ids[i], units[i]);
            }
        }
        vm.prank(msgSender);
        storageRent.batchRent{value: totalCost}(ids, units);

        // Expect rented units to increase
        assertEq(storageRent.rentedUnits(), rented + totalUnits);
        return totalCost;
    }

    function credit(address msgSender, uint256 id, uint256 units) public {
        uint256 rented = storageRent.rentedUnits();
        uint256 remaining = storageRent.maxUnits() - rented;
        vm.assume(remaining > 0);
        units = bound(units, 1, remaining);

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(msgSender, id, units);

        vm.prank(msgSender);
        storageRent.credit(id, units);

        // Expect rented units to increase
        assertEq(storageRent.rentedUnits(), rented + units);
    }

    function rentStorage(
        address msgSender,
        uint256 id,
        uint256 units
    ) public returns (uint256, uint256, uint256, uint256) {
        uint256 rented = storageRent.rentedUnits();
        uint256 remaining = storageRent.maxUnits() - rented;
        vm.assume(remaining > 0);
        units = bound(units, 1, remaining);
        uint256 price = storageRent.price(units);
        uint256 unitPrice = storageRent.unitPrice();
        vm.deal(msgSender, price);
        uint256 balanceBefore = msgSender.balance;

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(msgSender, id, units);

        vm.prank(msgSender);
        storageRent.rent{value: price}(id, units);

        uint256 balanceAfter = msgSender.balance;
        uint256 paid = balanceBefore - balanceAfter;
        uint256 unitPricePaid = paid / units;

        // Expect rented units to increase
        assertEq(storageRent.rentedUnits(), rented + units);
        return (price, unitPrice, paid, unitPricePaid);
    }

    /* solhint-disable-next-line no-empty-blocks */
    receive() external payable {}
}
