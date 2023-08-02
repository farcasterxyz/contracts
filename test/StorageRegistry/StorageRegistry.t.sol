// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {StorageRegistry} from "../../src/StorageRegistry.sol";
import {TransferHelper} from "../../src/lib/TransferHelper.sol";
import {StorageRegistryTestSuite, StorageRegistryHarness} from "./StorageRegistryTestSuite.sol";
import {MockChainlinkFeed} from "../Utils.sol";

/* solhint-disable state-visibility */

contract StorageRegistryTest is StorageRegistryTestSuite {
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
        assertEq(storageRegistry.VERSION(), "2023.07.12");
    }

    function testRoles() public {
        assertEq(storageRegistry.ownerRoleId(), keccak256("OWNER_ROLE"));
        assertEq(storageRegistry.operatorRoleId(), keccak256("OPERATOR_ROLE"));
        assertEq(storageRegistry.treasurerRoleId(), keccak256("TREASURER_ROLE"));
    }

    function testDefaultAdmin() public {
        assertTrue(storageRegistry.hasRole(storageRegistry.DEFAULT_ADMIN_ROLE(), roleAdmin));
    }

    function testPriceFeedDefault() public {
        assertEq(address(storageRegistry.priceFeed()), address(priceFeed));
    }

    function testUptimeFeedDefault() public {
        assertEq(address(storageRegistry.uptimeFeed()), address(uptimeFeed));
    }

    function testDeprecationTimestampDefault() public {
        assertEq(storageRegistry.deprecationTimestamp(), DEPLOYED_AT + INITIAL_RENTAL_PERIOD);
    }

    function testUsdUnitPriceDefault() public {
        assertEq(storageRegistry.usdUnitPrice(), INITIAL_USD_UNIT_PRICE);
    }

    function testMaxUnitsDefault() public {
        assertEq(storageRegistry.maxUnits(), INITIAL_MAX_UNITS);
    }

    function testRentedUnitsDefault() public {
        assertEq(storageRegistry.rentedUnits(), 0);
    }

    function testEthUSDPriceDefault() public {
        assertEq(storageRegistry.ethUsdPrice(), uint256(ETH_USD_PRICE));
    }

    function testPrevEthUSDPriceDefault() public {
        assertEq(storageRegistry.prevEthUsdPrice(), uint256(ETH_USD_PRICE));
    }

    function testLastPriceFeedUpdateDefault() public {
        assertEq(storageRegistry.lastPriceFeedUpdateTime(), block.timestamp);
    }

    function testLastPriceFeedUpdateBlockDefault() public {
        assertEq(storageRegistry.lastPriceFeedUpdateBlock(), block.number);
    }

    function testPriceFeedCacheDurationDefault() public {
        assertEq(storageRegistry.priceFeedCacheDuration(), INITIAL_PRICE_FEED_CACHE_DURATION);
    }

    function testPriceFeedMaxAgeDefault() public {
        assertEq(storageRegistry.priceFeedMaxAge(), INITIAL_PRICE_FEED_MAX_AGE);
    }

    function testUptimeFeedGracePeriodDefault() public {
        assertEq(storageRegistry.uptimeFeedGracePeriod(), INITIAL_UPTIME_FEED_GRACE_PERIOD);
    }

    function testFuzzInitialPrice(uint128 quantity) public {
        assertEq(storageRegistry.price(quantity), INITIAL_PRICE_IN_ETH * quantity);
    }

    function testInitialUnitPrice() public {
        assertEq(storageRegistry.unitPrice(), INITIAL_PRICE_IN_ETH);
    }

    function testInitialPriceUpdate() public {
        // Clear ethUsdPrice storage slot
        vm.store(address(storageRegistry), bytes32(uint256(11)), bytes32(0));
        assertEq(storageRegistry.ethUsdPrice(), 0);

        // Clear prevEthUsdPrice storage slot
        vm.store(address(storageRegistry), bytes32(uint256(12)), bytes32(0));
        assertEq(storageRegistry.prevEthUsdPrice(), 0);

        vm.prank(owner);
        storageRegistry.refreshPrice();

        assertEq(storageRegistry.ethUsdPrice(), uint256(ETH_USD_PRICE));
        assertEq(storageRegistry.prevEthUsdPrice(), uint256(ETH_USD_PRICE));
        assertEq(storageRegistry.ethUsdPrice(), storageRegistry.prevEthUsdPrice());
    }

    /*//////////////////////////////////////////////////////////////
                                  RENT
    //////////////////////////////////////////////////////////////*/

    function testFuzzRent(address msgSender, uint256 id, uint200 units) public {
        _rentStorage(msgSender, id, units);
    }

    function testFuzzRentRevertsZeroUnits(address msgSender, uint256 id) public {
        vm.deal(msgSender, storageRegistry.price(100));

        vm.prank(msgSender);
        vm.expectRevert(StorageRegistry.InvalidAmount.selector);
        storageRegistry.rent(id, 0);
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
        uint256 lastPriceFeedUpdateTime = storageRegistry.lastPriceFeedUpdateTime();
        uint256 lastPriceFeedUpdateBlock = storageRegistry.lastPriceFeedUpdateBlock();
        uint256 ethUsdPrice = storageRegistry.ethUsdPrice();
        uint256 prevEthUsdPrice = storageRegistry.prevEthUsdPrice();

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        _rentStorage(msgSender1, id1, units1);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        warp = bound(warp, 0, storageRegistry.priceFeedCacheDuration());
        vm.warp(block.timestamp + warp);

        _rentStorage(msgSender2, id2, units2);

        assertEq(storageRegistry.lastPriceFeedUpdateTime(), lastPriceFeedUpdateTime);
        assertEq(storageRegistry.lastPriceFeedUpdateBlock(), lastPriceFeedUpdateBlock);
        assertEq(storageRegistry.ethUsdPrice(), ethUsdPrice);
        assertEq(storageRegistry.prevEthUsdPrice(), prevEthUsdPrice);
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
        uint256 ethUsdPrice = storageRegistry.ethUsdPrice();

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);

        _rentStorage(msgSender1, id1, units1);

        // Set a new ETH/USD price
        priceFeed.setPrice(newEthUsdPrice);

        vm.warp(block.timestamp + storageRegistry.priceFeedCacheDuration() + 1);

        uint256 expectedPrice = storageRegistry.unitPrice();

        (, uint256 unitPrice,,) = _rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice, expectedPrice);
        assertEq(storageRegistry.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRegistry.lastPriceFeedUpdateBlock(), block.number);
        assertEq(storageRegistry.prevEthUsdPrice(), ethUsdPrice);
        assertEq(storageRegistry.ethUsdPrice(), uint256(newEthUsdPrice));
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
        uint256 ethUsdPrice = storageRegistry.ethUsdPrice();

        decrease = bound(decrease, 1, ethUsdPrice);
        uint256 newEthUsdPrice = ethUsdPrice - decrease;
        vm.assume(newEthUsdPrice > 0);

        // Set a new ETH/USD price
        priceFeed.setPrice(int256(newEthUsdPrice));

        vm.warp(block.timestamp + storageRegistry.priceFeedCacheDuration() + 1);

        (, uint256 unitPrice1,, uint256 unitPricePaid1) = _rentStorage(msgSender1, id1, units1);
        (, uint256 unitPrice2,, uint256 unitPricePaid2) = _rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice1, unitPrice2);
        assertEq(unitPricePaid1, unitPricePaid2);
        assertEq(unitPricePaid1, unitPrice1);
        assertEq(storageRegistry.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRegistry.lastPriceFeedUpdateBlock(), block.number);
        assertEq(storageRegistry.prevEthUsdPrice(), ethUsdPrice);
        assertEq(storageRegistry.ethUsdPrice(), newEthUsdPrice);
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
        uint256 ethUsdPrice = storageRegistry.ethUsdPrice();

        increase = bound(increase, 1, uint256(type(int256).max) - ethUsdPrice);
        uint256 newEthUsdPrice = ethUsdPrice + increase;

        // Set a new ETH/USD price
        priceFeed.setPrice(int256(newEthUsdPrice));

        vm.warp(block.timestamp + storageRegistry.priceFeedCacheDuration() + 1);

        (, uint256 unitPrice1,, uint256 unitPricePaid1) = _rentStorage(msgSender1, id1, units1);
        (, uint256 unitPrice2,, uint256 unitPricePaid2) = _rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice1, unitPrice2);
        assertEq(unitPricePaid1, unitPricePaid2);
        assertEq(unitPricePaid1, unitPrice1);
        assertEq(storageRegistry.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRegistry.lastPriceFeedUpdateBlock(), block.number);
        assertEq(storageRegistry.prevEthUsdPrice(), ethUsdPrice);
        assertEq(storageRegistry.ethUsdPrice(), newEthUsdPrice);
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
        uint256 lastPriceFeedUpdateTime = storageRegistry.lastPriceFeedUpdateTime();
        uint256 lastPriceFeedUpdateBlock = storageRegistry.lastPriceFeedUpdateBlock();
        uint256 prevEthUsdPrice = storageRegistry.prevEthUsdPrice();
        uint256 ethUsdPrice = storageRegistry.ethUsdPrice();

        // Ensure Chainlink price is positive
        newEthUsdPrice = bound(newEthUsdPrice, 1, type(int256).max);
        fixedPrice = bound(fixedPrice, 10e8, 100_000e8);

        _rentStorage(msgSender1, id1, units1);

        // Update the Chainlink price and fake a failure
        priceFeed.setPrice(newEthUsdPrice);
        priceFeed.setShouldRevert(true);

        // Set a fixed ETH/USD price, disabling price feeds
        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(fixedPrice);

        vm.warp(block.timestamp + storageRegistry.priceFeedCacheDuration() + 1);

        uint256 expectedPrice = storageRegistry.unitPrice();

        // Rent succeeds even though price feed is reverting
        (, uint256 unitPrice,,) = _rentStorage(msgSender2, id2, units2);

        assertEq(unitPrice, expectedPrice);

        // Price feed parameters do not change, since it's not refreshed
        assertEq(storageRegistry.lastPriceFeedUpdateTime(), lastPriceFeedUpdateTime);
        assertEq(storageRegistry.lastPriceFeedUpdateBlock(), lastPriceFeedUpdateBlock);
        assertEq(storageRegistry.prevEthUsdPrice(), prevEthUsdPrice);
        assertEq(storageRegistry.ethUsdPrice(), ethUsdPrice);
    }

    function testFuzzRentRevertsAfterDeadline(address msgSender, uint256 id, uint256 units) public {
        units = bound(units, 1, storageRegistry.maxUnits());
        uint256 price = storageRegistry.price(units);
        vm.deal(msgSender, price);

        vm.warp(storageRegistry.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRegistry.ContractDeprecated.selector);
        vm.prank(msgSender);
        storageRegistry.rent(id, units);
    }

    function testFuzzRentRevertsInsufficientPayment(
        address msgSender,
        uint256 id,
        uint256 units,
        uint256 delta
    ) public {
        units = bound(units, 1, storageRegistry.maxUnits());
        uint256 price = storageRegistry.price(units);
        uint256 value = price - bound(delta, 1, price);
        vm.deal(msgSender, value);

        vm.expectRevert(StorageRegistry.InvalidPayment.selector);
        vm.prank(msgSender);
        storageRegistry.rent{value: value}(id, units);
    }

    function testFuzzRentRefundsExcessPayment(uint256 id, uint256 units, uint256 delta) public {
        // Buy between 1 and maxUnits units.
        units = bound(units, 1, storageRegistry.maxUnits());

        // Ensure there are units remaining
        uint256 rented = storageRegistry.rentedUnits();
        uint256 remaining = storageRegistry.maxUnits() - rented;
        vm.assume(remaining > 0);

        units = bound(units, 1, remaining);
        // Add a fuzzed amount to the price.
        uint256 price = storageRegistry.price(units);
        uint256 extra = bound(delta, 1, type(uint256).max - price);
        vm.deal(address(this), price + extra);

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(address(this), id, units);

        storageRegistry.rent{value: price + extra}(id, units);

        assertEq(address(this).balance, extra);
    }

    function testFuzzRentFailedRefundRevertsCallFailed(uint256 id, uint256 units, uint256 delta) public {
        // Buy between 1 and maxUnits units.
        units = bound(units, 1, storageRegistry.maxUnits());

        // Ensure there are units remaining
        uint256 rented = storageRegistry.rentedUnits();
        uint256 remaining = storageRegistry.maxUnits() - rented;
        vm.assume(remaining > 0);

        units = bound(units, 1, remaining);
        // Add a fuzzed amount to the price.
        uint256 price = storageRegistry.price(units);
        uint256 extra = bound(delta, 1, type(uint256).max - price);
        vm.deal(address(revertOnReceive), price + extra);

        vm.prank(address(revertOnReceive));
        vm.expectRevert(TransferHelper.CallFailed.selector);
        storageRegistry.rent{value: price + extra}(id, units);
    }

    function testFuzzRentRevertsExceedsCapacity(address msgSender, uint256 id, uint256 units) public {
        // Buy all the available units.
        uint256 maxUnits = storageRegistry.maxUnits();
        uint256 maxUnitsPrice = storageRegistry.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRegistry.rent{value: maxUnitsPrice}(0, maxUnits);

        // Attempt to buy a fuzzed amount units.
        units = bound(units, 1, storageRegistry.maxUnits());
        uint256 price = storageRegistry.unitPrice() * units;
        vm.deal(msgSender, price);

        vm.expectRevert(StorageRegistry.ExceedsCapacity.selector);
        vm.prank(msgSender);
        storageRegistry.rent{value: price}(id, units);
    }

    /*//////////////////////////////////////////////////////////////
                               BATCH RENT
    //////////////////////////////////////////////////////////////*/

    function testFuzzBatchRent(address msgSender, uint256[] calldata _ids, uint16[] calldata _units) public {
        // Throw away runs with empty arrays.
        vm.assume(_ids.length > 0);
        vm.assume(_units.length > 0);

        // Set a high max capacity to avoid overflow.
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
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
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
        vm.stopPrank();

        uint256 lastPriceFeedUpdate = storageRegistry.lastPriceFeedUpdateTime();
        uint256 ethUsdPrice = storageRegistry.ethUsdPrice();

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

        warp = bound(warp, 0, storageRegistry.priceFeedCacheDuration());
        vm.warp(block.timestamp + warp);

        batchRentStorage(msgSender, ids, units);

        assertEq(storageRegistry.lastPriceFeedUpdateTime(), lastPriceFeedUpdate);
        assertEq(storageRegistry.ethUsdPrice(), ethUsdPrice);
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
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
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

        vm.warp(block.timestamp + storageRegistry.priceFeedCacheDuration() + 1);

        batchRentStorage(msgSender, ids, units);

        assertEq(storageRegistry.lastPriceFeedUpdateTime(), block.timestamp);
        assertEq(storageRegistry.ethUsdPrice(), uint256(newEthUsdPrice));
    }

    function testFuzzBatchRentRevertsAfterDeadline(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
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
        vm.warp(storageRegistry.deprecationTimestamp() + 1);
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }
        uint256 totalCost = storageRegistry.price(totalUnits);
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());
        vm.deal(msgSender, totalCost);
        vm.prank(msgSender);
        vm.expectRevert(StorageRegistry.ContractDeprecated.selector);
        storageRegistry.batchRent{value: totalCost}(ids, units);
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
        vm.expectRevert(StorageRegistry.InvalidBatchInput.selector);
        storageRegistry.batchRent{value: 0}(ids, units);
    }

    function testFuzzBatchRentRevertsMismatchedArrayLength(
        address msgSender,
        uint256[] calldata _ids,
        uint16[] calldata _units
    ) public {
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
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
        uint256 totalCost = storageRegistry.price(totalUnits);
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());
        vm.deal(msgSender, totalCost);

        vm.prank(msgSender);
        vm.expectRevert(StorageRegistry.InvalidBatchInput.selector);
        storageRegistry.batchRent{value: totalCost}(ids, units);
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
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
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
        uint256 totalCost = storageRegistry.price(totalUnits);
        uint256 value = totalCost - bound(delta, 1, totalCost);
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());
        vm.deal(msgSender, totalCost);

        vm.prank(msgSender);
        vm.expectRevert(StorageRegistry.InvalidPayment.selector);
        storageRegistry.batchRent{value: value}(ids, units);
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
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
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
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());

        // Add an extra fuzzed amount to the required payment
        uint256 totalCost = storageRegistry.price(totalUnits);
        uint256 extra = bound(delta, 1, type(uint256).max - totalCost);
        uint256 value = totalCost + extra;

        vm.deal(address(this), value);
        storageRegistry.batchRent{value: value}(ids, units);

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
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(type(uint256).max);
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
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());

        // Add an extra fuzzed amount to the required payment
        uint256 totalCost = storageRegistry.price(totalUnits);
        uint256 extra = bound(delta, 1, type(uint256).max - totalCost);
        uint256 value = totalCost + extra;

        vm.deal(address(revertOnReceive), value);
        vm.prank(address(revertOnReceive));
        vm.expectRevert(TransferHelper.CallFailed.selector);
        storageRegistry.batchRent{value: value}(ids, units);
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
        vm.startPrank(owner);
        storageRegistry.setMaxUnits(10_000_000);
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
        uint256 maxUnits = storageRegistry.maxUnits();
        uint256 maxUnitsPrice = storageRegistry.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRegistry.rent{value: maxUnitsPrice}(0, maxUnits);

        uint256 totalPrice = storageRegistry.price(totalUnits);
        vm.deal(msgSender, totalPrice);
        vm.expectRevert(StorageRegistry.ExceedsCapacity.selector);
        vm.prank(msgSender);
        storageRegistry.batchRent{value: totalPrice}(ids, units);
    }

    function testBatchRentCheckedMath() public {
        uint256[] memory fids = new uint256[](1);
        uint256[] memory units = new uint256[](1);
        units[0] = type(uint256).max;

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        storageRegistry.batchRent(fids, units);
    }

    /*//////////////////////////////////////////////////////////////
                               UNIT PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzUnitPriceRefresh(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        priceFeed.setPrice(ethUsdPrice);
        vm.startPrank(owner);
        storageRegistry.refreshPrice();
        storageRegistry.setPrice(usdUnitPrice);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(storageRegistry.unitPrice(), (uint256(usdUnitPrice)).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzUnitPriceCached(uint48 usdUnitPrice, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = storageRegistry.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);

        vm.prank(owner);
        storageRegistry.setPrice(usdUnitPrice);

        assertEq(storageRegistry.unitPrice(), uint256(usdUnitPrice) * 1e18 / cachedPrice);
    }

    /*//////////////////////////////////////////////////////////////
                                  PRICE
    //////////////////////////////////////////////////////////////*/

    function testPriceRoundsUp() public {
        priceFeed.setPrice(1e18 + 1);

        vm.startPrank(owner);
        storageRegistry.refreshPrice();
        storageRegistry.setPrice(1);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(storageRegistry.price(1), 1);
    }

    function testFuzzPrice(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        priceFeed.setPrice(ethUsdPrice);
        vm.startPrank(owner);
        storageRegistry.refreshPrice();
        storageRegistry.setPrice(usdUnitPrice);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(storageRegistry.price(units), (uint256(usdUnitPrice) * units).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzPriceCached(uint48 usdUnitPrice, uint128 units, int256 ethUsdPrice) public {
        // Ensure Chainlink price is positive
        ethUsdPrice = bound(ethUsdPrice, 1, type(int256).max);

        uint256 cachedPrice = storageRegistry.ethUsdPrice();

        priceFeed.setPrice(ethUsdPrice);
        vm.prank(owner);
        storageRegistry.setPrice(usdUnitPrice);

        assertEq(storageRegistry.price(units), (uint256(usdUnitPrice) * units).divWadUp(cachedPrice));
    }

    /*//////////////////////////////////////////////////////////////
                               PRICE FEED
    //////////////////////////////////////////////////////////////*/

    function testFuzzPriceFeedRevertsInvalidPrice(int256 price) public {
        // Ensure price is zero or negative
        price = price > 0 ? -price : price;
        priceFeed.setPrice(price);

        vm.expectRevert(StorageRegistry.InvalidPrice.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
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

        vm.expectRevert(StorageRegistry.StaleAnswer.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
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

        vm.expectRevert(StorageRegistry.StaleAnswer.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
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
        vm.expectRevert(StorageRegistry.IncompleteRound.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
    }

    function testFuzzPriceFeedFailure(address msgSender, uint256 id, uint256 units) public {
        units = bound(units, 1, storageRegistry.maxUnits());
        uint256 price = storageRegistry.price(units);
        vm.deal(msgSender, price);

        // Fake a price feed error and ensure the next call will refresh the price.
        priceFeed.setShouldRevert(true);
        vm.warp(block.timestamp + storageRegistry.priceFeedCacheDuration() + 1);

        // Calling rent reverts.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(msgSender);
        storageRegistry.rent{value: price}(id, units);

        // Owner can set a failsafe fixed price.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, 4000e8);
        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(4000e8);

        // ETH doubled in USD terms, so we need
        // half as much for the same USD price.
        uint256 newPrice = storageRegistry.price(units);
        assertEq(newPrice, price / 2);

        // Calling rent now succeeds.
        vm.prank(msgSender);
        storageRegistry.rent{value: newPrice}(id, units);

        // Setting fixed price back to zero re-enables the price feed.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(4000e8, 0);
        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(0);

        // Calls revert again, since price feed is re-enabled.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(owner);
        storageRegistry.refreshPrice();
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

        vm.expectRevert(StorageRegistry.SequencerDown.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
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

        vm.expectRevert(StorageRegistry.StaleAnswer.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
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
        vm.expectRevert(StorageRegistry.IncompleteRound.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
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

        vm.expectRevert(StorageRegistry.GracePeriodNotOver.selector);
        vm.prank(owner);
        storageRegistry.refreshPrice();
    }

    function testFuzzUptimeFeedFailure(address msgSender, uint256 id, uint256 units) public {
        units = bound(units, 1, storageRegistry.maxUnits());
        uint256 price = storageRegistry.price(units);
        vm.deal(msgSender, price);

        // Fake an uptime feed error and ensure the next call will refresh the price.
        uptimeFeed.setShouldRevert(true);
        vm.warp(block.timestamp + storageRegistry.priceFeedCacheDuration() + 1);

        // Calling rent reverts
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(msgSender);
        storageRegistry.rent{value: price}(id, units);

        // Owner can set a failsafe fixed price.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, 4000e8);
        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(4000e8);

        // ETH doubled in USD terms, so we need
        // half as much for the same USD price.
        uint256 newPrice = storageRegistry.price(units);
        assertEq(newPrice, price / 2);

        // Calling rent now succeeds.
        vm.prank(msgSender);
        storageRegistry.rent{value: newPrice}(id, units);

        // Setting fixed price back to zero re-enables the price feed.
        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(4000e8, 0);
        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(0);

        // Calls revert again, since price feed is re-enabled.
        vm.expectRevert("MockChainLinkFeed: Call failed");
        vm.prank(owner);
        storageRegistry.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                              REFRESH PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAuthorizedCanRefreshPrice(address caller) public {
        vm.assume(caller != owner && caller != treasurer);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.Unauthorized.selector);
        storageRegistry.refreshPrice();
    }

    /*//////////////////////////////////////////////////////////////
                                 CREDIT
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOperatorCanCredit(address caller, uint256 fid, uint256 units) public {
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOperator.selector);
        storageRegistry.credit(fid, units);
    }

    function testFuzzCredit(uint256 fid, uint32 units) public {
        credit(operator, fid, units);
    }

    function testFuzzCreditRevertsExceedsCapacity(uint256 fid, uint32 units) public {
        // Buy all the available units.
        uint256 maxUnits = storageRegistry.maxUnits();
        uint256 maxUnitsPrice = storageRegistry.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRegistry.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRegistry.ExceedsCapacity.selector);
        vm.prank(operator);
        storageRegistry.credit(fid, units);
    }

    function testFuzzCreditRevertsAfterDeadline(uint256 fid, uint32 units) public {
        vm.warp(storageRegistry.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRegistry.ContractDeprecated.selector);
        vm.prank(operator);
        storageRegistry.credit(fid, units);
    }

    function testFuzzCreditRevertsZeroUnits(uint256 fid) public {
        vm.expectRevert(StorageRegistry.InvalidAmount.selector);
        vm.prank(operator);
        storageRegistry.credit(fid, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              BATCH CREDIT
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOperatorCanBatchCredit(address caller, uint256[] calldata fids, uint256 units) public {
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOperator.selector);
        storageRegistry.batchCredit(fids, units);
    }

    function testFuzzBatchCredit(uint256[] calldata fids, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        batchCredit(fids, units);
    }

    function testFuzzBatchCreditRevertsZeroAmount(uint256[] calldata fids) public {
        vm.expectRevert(StorageRegistry.InvalidAmount.selector);
        vm.prank(operator);
        storageRegistry.batchCredit(fids, 0);
    }

    function testFuzzBatchCreditRevertsExceedsCapacity(uint256[] calldata fids, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        vm.assume(fids.length > 0);

        // Buy all the available units.
        uint256 maxUnits = storageRegistry.maxUnits();
        uint256 maxUnitsPrice = storageRegistry.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRegistry.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRegistry.ExceedsCapacity.selector);
        vm.prank(operator);
        storageRegistry.batchCredit(fids, units);
    }

    function testFuzzBatchCreditRevertsAfterDeadline(uint256[] calldata fids, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        vm.warp(storageRegistry.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRegistry.ContractDeprecated.selector);
        vm.prank(operator);
        storageRegistry.batchCredit(fids, units);
    }

    /*//////////////////////////////////////////////////////////////
                            CONTINUOUS CREDIT
    //////////////////////////////////////////////////////////////*/

    function testOnlyOperatorCanContinuousCredit(address caller, uint16 start, uint256 n, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        uint256 end = uint256(start) + bound(n, 1, 10000);
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOperator.selector);
        storageRegistry.continuousCredit(start, end, units);
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

        vm.expectRevert(StorageRegistry.InvalidAmount.selector);
        vm.prank(operator);
        storageRegistry.continuousCredit(start, end, 0);
    }

    function testFuzzContinuousCreditRevertsExceedsCapacity(uint16 start, uint256 n, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        uint256 end = uint256(start) + bound(n, 1, 10000);

        // Buy all the available units.
        uint256 maxUnits = storageRegistry.maxUnits();
        uint256 maxUnitsPrice = storageRegistry.price(maxUnits);
        vm.deal(address(this), maxUnitsPrice);
        storageRegistry.rent{value: maxUnitsPrice}(0, maxUnits);
        units = uint32(bound(units, 1, type(uint32).max));

        vm.expectRevert(StorageRegistry.ExceedsCapacity.selector);
        vm.prank(operator);
        storageRegistry.continuousCredit(start, end, units);
    }

    function testFuzzContinuousCreditRevertsAfterDeadline(uint16 start, uint256 n, uint32 _units) public {
        uint256 units = bound(_units, 1, type(uint32).max);
        uint256 end = uint256(start) + bound(n, 0, 10000);
        vm.warp(storageRegistry.deprecationTimestamp() + 1);

        vm.expectRevert(StorageRegistry.ContractDeprecated.selector);
        vm.prank(operator);
        storageRegistry.continuousCredit(start, end, units);
    }

    /*//////////////////////////////////////////////////////////////
                           SET USD UNIT PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerOrTreasurerCanSetUSDUnitPrice(address caller, uint256 unitPrice) public {
        vm.assume(caller != owner && caller != treasurer);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.Unauthorized.selector);
        storageRegistry.setPrice(unitPrice);
    }

    function testFuzzSetUSDUnitPrice(uint256 unitPrice) public {
        uint256 currentPrice = storageRegistry.usdUnitPrice();

        vm.expectEmit(false, false, false, true);
        emit SetPrice(currentPrice, unitPrice);

        vm.prank(owner);
        storageRegistry.setPrice(unitPrice);

        assertEq(storageRegistry.usdUnitPrice(), unitPrice);
    }

    /*//////////////////////////////////////////////////////////////
                           SET FIXED ETH PRICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetFixedEthUsdPrice(address caller, uint256 fixedPrice) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOwner.selector);
        storageRegistry.setFixedEthUsdPrice(fixedPrice);
    }

    function testFuzzSetFixedEthUsdPrice(uint256 fixedPrice) public {
        assertEq(storageRegistry.fixedEthUsdPrice(), 0);

        vm.expectEmit(false, false, false, true);
        emit SetFixedEthUsdPrice(0, fixedPrice);

        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(fixedPrice);

        assertEq(storageRegistry.fixedEthUsdPrice(), fixedPrice);
    }

    function testFuzzSetFixedEthUsdPriceOverridesPriceFeed(uint256 fixedPrice) public {
        vm.assume(fixedPrice != storageRegistry.ethUsdPrice());
        fixedPrice = bound(fixedPrice, 1, type(uint256).max);

        uint256 usdUnitPrice = storageRegistry.usdUnitPrice();
        uint256 priceBefore = storageRegistry.unitPrice();

        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(fixedPrice);

        uint256 priceAfter = storageRegistry.unitPrice();

        assertTrue(priceBefore != priceAfter);
        assertEq(priceAfter, usdUnitPrice.divWadUp(fixedPrice));
    }

    function testFuzzRemoveFixedEthUsdPriceReenablesPriceFeed(uint256 fixedPrice) public {
        vm.assume(fixedPrice != storageRegistry.ethUsdPrice());
        fixedPrice = bound(fixedPrice, 1, type(uint256).max);

        uint256 usdUnitPrice = storageRegistry.usdUnitPrice();
        uint256 priceBefore = storageRegistry.unitPrice();

        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(fixedPrice);

        uint256 priceAfter = storageRegistry.unitPrice();

        assertTrue(priceBefore != priceAfter);
        assertEq(priceAfter, usdUnitPrice.divWadUp(fixedPrice));

        vm.prank(owner);
        storageRegistry.setFixedEthUsdPrice(0);
        assertEq(storageRegistry.fixedEthUsdPrice(), 0);

        uint256 priceFinal = storageRegistry.unitPrice();
        assertEq(priceBefore, priceFinal);
    }

    /*//////////////////////////////////////////////////////////////
                              SET MAX UNITS
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetMaxUnits(address caller, uint256 maxUnits) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOwner.selector);
        storageRegistry.setMaxUnits(maxUnits);
    }

    function testFuzzSetMaxUnitsEmitsEvent(uint256 maxUnits) public {
        uint256 currentMax = storageRegistry.maxUnits();

        vm.expectEmit(false, false, false, true);
        emit SetMaxUnits(currentMax, maxUnits);

        vm.prank(owner);
        storageRegistry.setMaxUnits(maxUnits);

        assertEq(storageRegistry.maxUnits(), maxUnits);
    }

    function testFuzzOnlyOwnerCanSetDeprecationTime(address caller, uint256 timestamp) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOwner.selector);
        storageRegistry.setDeprecationTimestamp(timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        SET DEPRECATION TIMESTAMP
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetDeprecationTime(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, type(uint256).max);
        uint256 currentEnd = storageRegistry.deprecationTimestamp();

        vm.expectEmit(false, false, false, true);
        emit SetDeprecationTimestamp(currentEnd, timestamp);

        vm.prank(owner);
        storageRegistry.setDeprecationTimestamp(timestamp);

        assertEq(storageRegistry.deprecationTimestamp(), timestamp);
    }

    function testFuzzSetDeprecationTimeRevertsInPast() public {
        vm.expectRevert(StorageRegistry.InvalidDeprecationTimestamp.selector);
        vm.prank(owner);
        storageRegistry.setDeprecationTimestamp(block.timestamp - 1);
    }

    /*//////////////////////////////////////////////////////////////
                           SET CACHE DURATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetCacheDuration(address caller, uint256 duration) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOwner.selector);
        storageRegistry.setCacheDuration(duration);
    }

    function testFuzzSetCacheDuration(uint256 duration) public {
        uint256 currentDuration = storageRegistry.priceFeedCacheDuration();

        vm.expectEmit(false, false, false, true);
        emit SetCacheDuration(currentDuration, duration);

        vm.prank(owner);
        storageRegistry.setCacheDuration(duration);

        assertEq(storageRegistry.priceFeedCacheDuration(), duration);
    }

    /*//////////////////////////////////////////////////////////////
                           SET MAX PRICE AGE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetMaxAge(address caller, uint256 age) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOwner.selector);
        storageRegistry.setMaxAge(age);
    }

    function testFuzzSetMaxAge(uint256 age) public {
        uint256 currentAge = storageRegistry.priceFeedMaxAge();

        vm.expectEmit(false, false, false, true);
        emit SetMaxAge(currentAge, age);

        vm.prank(owner);
        storageRegistry.setMaxAge(age);

        assertEq(storageRegistry.priceFeedMaxAge(), age);
    }

    /*//////////////////////////////////////////////////////////////
                            SET GRACE PERIOD
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetGracePeriod(address caller, uint256 duration) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOwner.selector);
        storageRegistry.setGracePeriod(duration);
    }

    function testFuzzSetGracePeriod(uint256 duration) public {
        uint256 currentGracePeriod = storageRegistry.uptimeFeedGracePeriod();

        vm.expectEmit(false, false, false, true);
        emit SetGracePeriod(currentGracePeriod, duration);

        vm.prank(owner);
        storageRegistry.setGracePeriod(duration);

        assertEq(storageRegistry.uptimeFeedGracePeriod(), duration);
    }

    /*//////////////////////////////////////////////////////////////
                                SET VAULT
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetVault(address newVault) public {
        vm.assume(newVault != address(0));
        vm.expectEmit(false, false, false, true);
        emit SetVault(vault, newVault);

        vm.prank(owner);
        storageRegistry.setVault(newVault);

        assertEq(storageRegistry.vault(), newVault);
    }

    function testFuzzOnlyOwnerCanSetVault(address caller, address vault) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotOwner.selector);
        storageRegistry.setVault(vault);
    }

    function testSetVaultCannotBeZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(StorageRegistry.InvalidAddress.selector);
        storageRegistry.setVault(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function testFuzzWithdrawal(address msgSender, uint256 id, uint200 units, uint256 amount) public {
        uint256 balanceBefore = address(vault).balance;

        _rentStorage(msgSender, id, units);

        // Don't withdraw more than the contract balance
        amount = bound(amount, 0, address(storageRegistry).balance);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(vault, amount);

        vm.prank(treasurer);
        storageRegistry.withdraw(amount);

        uint256 balanceAfter = address(vault).balance;
        uint256 balanceChange = balanceAfter - balanceBefore;

        assertEq(balanceChange, amount);
    }

    function testFuzzWithdrawalRevertsInsufficientFunds(uint256 amount) public {
        // Ensure amount is positive
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(treasurer);
        vm.expectRevert(TransferHelper.CallFailed.selector);
        storageRegistry.withdraw(amount);
    }

    function testFuzzWithdrawalRevertsCallFailed() public {
        uint256 price = storageRegistry.price(1);
        storageRegistry.rent{value: price}(1, 1);

        vm.prank(owner);
        storageRegistry.setVault(address(revertOnReceive));

        vm.prank(treasurer);
        vm.expectRevert(TransferHelper.CallFailed.selector);
        storageRegistry.withdraw(price);
    }

    function testFuzzOnlyTreasurerCanWithdraw(address caller, uint256 amount) public {
        vm.assume(caller != treasurer);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.NotTreasurer.selector);
        storageRegistry.withdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function continuousCredit(uint256 start, uint256 end, uint256 units, bool assertEvents) public {
        uint256 rented = storageRegistry.rentedUnits();
        uint256 len = end - start;
        uint256 totalUnits = len * units;
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());

        if (assertEvents) {
            // Expect emitted events
            for (uint256 i; i < len; ++i) {
                vm.expectEmit(true, true, false, true);
                emit Rent(operator, start + i, units);
            }
        }

        vm.prank(operator);
        storageRegistry.continuousCredit(start, end, units);

        // Expect rented units to increase
        assertEq(storageRegistry.rentedUnits(), rented + totalUnits);
    }

    function batchCredit(uint256[] memory ids, uint256 units) public {
        uint256 rented = storageRegistry.rentedUnits();
        uint256 totalUnits = ids.length * units;
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());

        // Expect emitted events
        for (uint256 i; i < ids.length; ++i) {
            vm.expectEmit(true, true, false, true);
            emit Rent(operator, ids[i], units);
        }
        vm.prank(operator);
        storageRegistry.batchCredit(ids, units);

        // Expect rented units to increase
        assertEq(storageRegistry.rentedUnits(), rented + totalUnits);
    }

    function batchRentStorage(
        address msgSender,
        uint256[] memory ids,
        uint256[] memory units
    ) public returns (uint256) {
        uint256 rented = storageRegistry.rentedUnits();
        uint256 totalUnits;
        for (uint256 i; i < units.length; ++i) {
            totalUnits += units[i];
        }
        uint256 totalCost = storageRegistry.price(totalUnits);
        vm.deal(msgSender, totalCost);
        vm.assume(totalUnits <= storageRegistry.maxUnits() - storageRegistry.rentedUnits());

        // Expect emitted events
        for (uint256 i; i < ids.length; ++i) {
            if (units[i] != 0) {
                vm.expectEmit(true, true, false, true);
                emit Rent(msgSender, ids[i], units[i]);
            }
        }
        vm.prank(msgSender);
        storageRegistry.batchRent{value: totalCost}(ids, units);

        // Expect rented units to increase
        assertEq(storageRegistry.rentedUnits(), rented + totalUnits);
        return totalCost;
    }

    function credit(address msgSender, uint256 id, uint256 units) public {
        uint256 rented = storageRegistry.rentedUnits();
        uint256 remaining = storageRegistry.maxUnits() - rented;
        vm.assume(remaining > 0);
        units = bound(units, 1, remaining);

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(msgSender, id, units);

        vm.prank(msgSender);
        storageRegistry.credit(id, units);

        // Expect rented units to increase
        assertEq(storageRegistry.rentedUnits(), rented + units);
    }

    function _rentStorage(
        address msgSender,
        uint256 id,
        uint256 units
    ) public returns (uint256, uint256, uint256, uint256) {
        uint256 rented = storageRegistry.rentedUnits();
        uint256 remaining = storageRegistry.maxUnits() - rented;
        vm.assume(remaining > 0);
        units = bound(units, 1, remaining);
        uint256 price = storageRegistry.price(units);
        uint256 unitPrice = storageRegistry.unitPrice();
        vm.deal(msgSender, price);
        uint256 balanceBefore = msgSender.balance;

        // Expect emitted event
        vm.expectEmit(true, true, false, true);
        emit Rent(msgSender, id, units);

        vm.prank(msgSender);
        storageRegistry.rent{value: price}(id, units);

        uint256 balanceAfter = msgSender.balance;
        uint256 paid = balanceBefore - balanceAfter;
        uint256 unitPricePaid = paid / units;

        // Expect rented units to increase
        assertEq(storageRegistry.rentedUnits(), rented + units);
        return (price, unitPrice, paid, unitPricePaid);
    }

    /* solhint-disable-next-line no-empty-blocks */
    receive() external payable {}
}
