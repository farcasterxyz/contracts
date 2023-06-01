// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {IdRegistry} from "../src/IdRegistry.sol";
import {StorageRegistry} from "../src/StorageRegistry.sol";

/* solhint-disable no-empty-blocks */

/**
 * @dev IdRegistryHarness exposes IdRegistry's private methods for test assertions.
 */
contract IdRegistryHarness is IdRegistry {
    constructor(address forwarder) IdRegistry(forwarder) {}

    function getIdCounter() public view returns (uint256) {
        return idCounter;
    }

    function getRecoveryOf(uint256 id) public view returns (address) {
        return recoveryOf[id];
    }

    function getRecoveryTsOf(uint256 id) public view returns (uint256) {
        return uint256(recoveryStateOf[id].startTs);
    }

    function getRecoveryDestinationOf(uint256 id) public view returns (address) {
        return recoveryStateOf[id].destination;
    }

    function getTrustedCaller() public view returns (address) {
        return trustedCaller;
    }

    function getTrustedOnly() public view returns (uint256) {
        return trustedOnly;
    }

    function getPendingOwner() public view returns (address) {
        return pendingOwner;
    }
}

contract StorageRegistryHarness is StorageRegistry {
    constructor(
        AggregatorV3Interface _priceFeed,
        AggregatorV3Interface _uptimeFeed,
        uint256 _rentalPeriod,
        uint256 _usdUnitPrice,
        uint256 _maxUnits
    ) StorageRegistry(_priceFeed, _uptimeFeed, _rentalPeriod, _usdUnitPrice, _maxUnits) {}
}

contract MockPriceFeed is AggregatorV3Interface {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 timeStamp;
        uint80 answeredInRound;
    }

    RoundData public roundData;

    uint8 public decimals = 8;
    string public description = "Mock ETH/USD Price Feed";
    uint256 public version = 1;

    function setPrice(int256 _price) external {
        roundData.answer = _price;
    }

    function setRoundData(RoundData calldata _roundData) external {
        roundData = _roundData;
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return latestRoundData();
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return
            (roundData.roundId, roundData.answer, roundData.startedAt, roundData.timeStamp, roundData.answeredInRound);
    }
}

contract MockUptimeFeed is AggregatorV3Interface {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 timeStamp;
        uint80 answeredInRound;
    }

    RoundData public roundData;

    uint8 public decimals = 0;
    string public description = "Mock L2 Sequencer Uptime Feed";
    uint256 public version = 1;

    function setAnswer(int256 _answer) external {
        roundData.answer = _answer;
    }

    function setRoundData(RoundData calldata _roundData) external {
        roundData = _roundData;
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return latestRoundData();
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        return
            (roundData.roundId, roundData.answer, roundData.startedAt, roundData.timeStamp, roundData.answeredInRound);
    }
}

contract RevertOnReceive {
    receive() external payable {
        revert("Cannot receive ETH");
    }
}
