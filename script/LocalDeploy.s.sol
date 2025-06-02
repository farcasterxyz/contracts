// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {IdRegistry} from "../src/IdRegistry.sol";
import {StorageRegistry} from "../src/StorageRegistry.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";
import {MockPriceFeed, MockUptimeFeed, MockChainlinkFeed} from "../test/Utils.sol";

contract LocalDeploy is Script {
    uint256 internal constant INITIAL_RENTAL_PERIOD = 365 days;
    uint256 internal constant INITIAL_USD_UNIT_PRICE = 5e8; // $5 USD
    uint256 internal constant INITIAL_MAX_UNITS = 2_000_000;
    uint256 internal constant INITIAL_PRICE_FEED_CACHE_DURATION = 1 days;
    uint256 internal constant INITIAL_UPTIME_FEED_GRACE_PERIOD = 1 hours;

    bytes32 internal constant ID_REGISTRY_CREATE2_SALT = "fc";
    bytes32 internal constant KEY_REGISTRY_CREATE2_SALT = "fc";
    bytes32 internal constant STORAGE_RENT_CREATE2_SALT = "fc";

    function run() public {
        _etchCreate2Deployer();

        address initialIdRegistryOwner = vm.envAddress("ID_REGISTRY_OWNER_ADDRESS");
        address initialKeyRegistryOwner = vm.envAddress("KEY_REGISTRY_OWNER_ADDRESS");

        address vault = vm.envAddress("STORAGE_RENT_VAULT_ADDRESS");
        address roleAdmin = vm.envAddress("STORAGE_RENT_ROLE_ADMIN_ADDRESS");
        address admin = vm.envAddress("STORAGE_RENT_ADMIN_ADDRESS");
        address operator = vm.envAddress("STORAGE_RENT_OPERATOR_ADDRESS");
        address treasurer = vm.envAddress("STORAGE_RENT_TREASURER_ADDRESS");
        address migrator = vm.envAddress("MIGRATOR_ADDRESS");

        vm.startBroadcast();
        (AggregatorV3Interface priceFeed, AggregatorV3Interface uptimeFeed) = _getOrDeployPriceFeeds();
        IdRegistry idRegistry = new IdRegistry{salt: ID_REGISTRY_CREATE2_SALT}(migrator, initialIdRegistryOwner);
        KeyRegistry keyRegistry = new KeyRegistry{salt: KEY_REGISTRY_CREATE2_SALT}(
            address(idRegistry), migrator, initialKeyRegistryOwner, 1000
        );
        StorageRegistry storageRegistry = new StorageRegistry{salt: STORAGE_RENT_CREATE2_SALT}(
            priceFeed,
            uptimeFeed,
            INITIAL_USD_UNIT_PRICE,
            INITIAL_MAX_UNITS,
            vault,
            roleAdmin,
            admin,
            operator,
            treasurer
        );
        vm.stopBroadcast();
        console.log("ID Registry: %s", address(idRegistry));
        console.log("Key Registry: %s", address(keyRegistry));
        console.log("Storage Rent: %s", address(storageRegistry));
    }

    /* @dev Make an Anvil RPC call to deploy the same CREATE2 deployer Foundry uses on mainnet. */
    function _etchCreate2Deployer() internal {
        if (block.chainid == 31337) {
            string[] memory command = new string[](5);
            command[0] = "cast";
            command[1] = "rpc";
            command[2] = "anvil_setCode";
            command[3] = "0x4e59b44847b379578588920cA78FbF26c0B4956C";
            command[4] = (
                "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
                "e03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
            );
            vm.ffi(command);
        }
    }

    /* @dev Warp block.timestamp forward 3600 seconds, beyond the uptime feed grace period. */
    function _warpForward() internal {
        if (block.chainid == 31337) {
            string[] memory command = new string[](4);
            command[0] = "cast";
            command[1] = "rpc";
            command[2] = "evm_increaseTime";
            command[3] = "0xe10";
            vm.ffi(command);
        }
    }

    /* @dev Deploy mock price feeds if we're on Anvil, otherwise read their addresses from the environment. */
    function _getOrDeployPriceFeeds()
        internal
        returns (AggregatorV3Interface priceFeed, AggregatorV3Interface uptimeFeed)
    {
        if (block.chainid == 31337) {
            MockPriceFeed _priceFeed = new MockPriceFeed{salt: bytes32(0)}();
            MockUptimeFeed _uptimeFeed = new MockUptimeFeed{salt: bytes32(0)}();
            _priceFeed.setRoundData(
                MockChainlinkFeed.RoundData({
                    roundId: 1,
                    answer: 2000e8,
                    startedAt: 0,
                    timeStamp: block.timestamp,
                    answeredInRound: 1
                })
            );
            _uptimeFeed.setRoundData(
                MockChainlinkFeed.RoundData({
                    roundId: 1,
                    answer: 0,
                    startedAt: 0,
                    timeStamp: block.timestamp,
                    answeredInRound: 1
                })
            );
            _warpForward();
            priceFeed = _priceFeed;
            uptimeFeed = _uptimeFeed;
        } else {
            priceFeed = AggregatorV3Interface(vm.envAddress("STORAGE_RENT_PRICE_FEED_ADDRESS"));
            uptimeFeed = AggregatorV3Interface(vm.envAddress("STORAGE_RENT_UPTIME_FEED_ADDRESS"));
        }
    }
}
