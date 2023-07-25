// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {StorageRent} from "../src/StorageRent.sol";

contract StorageRentScript is Script {
    uint256 internal constant INITIAL_RENTAL_PERIOD = 365 days;
    uint256 internal constant INITIAL_USD_UNIT_PRICE = 5e8; // $5 USD
    uint256 internal constant INITIAL_MAX_UNITS = 2_000_000;
    uint256 internal constant INITIAL_PRICE_FEED_CACHE_DURATION = 1 days;
    uint256 internal constant INITIAL_UPTIME_FEED_GRACE_PERIOD = 1 hours;

    bytes32 internal constant CREATE2_SALT = "fc";

    function run() public {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(vm.envAddress("STORAGE_RENT_PRICE_FEED_ADDRESS"));
        AggregatorV3Interface uptimeFeed = AggregatorV3Interface(vm.envAddress("STORAGE_RENT_UPTIME_FEED_ADDRESS"));
        address vault = vm.envAddress("STORAGE_RENT_VAULT_ADDRESS");
        address roleAdmin = vm.envAddress("STORAGE_RENT_ROLE_ADMIN_ADDRESS");
        address admin = vm.envAddress("STORAGE_RENT_ADMIN_ADDRESS");
        address operator = vm.envAddress("STORAGE_RENT_OPERATOR_ADDRESS");
        address treasurer = vm.envAddress("STORAGE_RENT_TREASURER_ADDRESS");

        vm.broadcast();
        new StorageRent{ salt: CREATE2_SALT }(
            priceFeed,
            uptimeFeed,
            INITIAL_RENTAL_PERIOD,
            INITIAL_USD_UNIT_PRICE,
            INITIAL_MAX_UNITS,
            vault,
            roleAdmin,
            admin,
            operator,
            treasurer
        );
    }
}
