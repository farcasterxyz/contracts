// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {StorageRegistry} from "../src/StorageRegistry.sol";
import {ImmutableCreate2Deployer} from "./abstract/ImmutableCreate2Deployer.sol";

contract StorageRegistryScript is ImmutableCreate2Deployer {
    uint256 internal constant INITIAL_RENTAL_PERIOD = 365 days;
    uint256 internal constant INITIAL_USD_UNIT_PRICE = 5e8; // $5 USD
    uint256 internal constant INITIAL_MAX_UNITS = 2_000_000;
    uint256 internal constant INITIAL_PRICE_FEED_CACHE_DURATION = 1 days;
    uint256 internal constant INITIAL_UPTIME_FEED_GRACE_PERIOD = 1 hours;

    function run() public {
        address priceFeed = vm.envAddress("STORAGE_RENT_PRICE_FEED_ADDRESS");
        address uptimeFeed = vm.envAddress("STORAGE_RENT_UPTIME_FEED_ADDRESS");
        address vault = vm.envAddress("STORAGE_RENT_VAULT_ADDRESS");
        address roleAdmin = vm.envAddress("STORAGE_RENT_ROLE_ADMIN_ADDRESS");
        address admin = vm.envAddress("STORAGE_RENT_ADMIN_ADDRESS");
        address operator = vm.envAddress("STORAGE_RENT_OPERATOR_ADDRESS");
        address treasurer = vm.envAddress("STORAGE_RENT_TREASURER_ADDRESS");

        register(
            "StorageRegistry",
            type(StorageRegistry).creationCode,
            abi.encode(
                priceFeed,
                uptimeFeed,
                INITIAL_RENTAL_PERIOD,
                INITIAL_USD_UNIT_PRICE,
                INITIAL_MAX_UNITS,
                vault,
                roleAdmin,
                admin,
                operator,
                treasurer,
                INITIAL_PRICE_FEED_CACHE_DURATION,
                INITIAL_UPTIME_FEED_GRACE_PERIOD
            )
        );

        deploy();
    }
}
