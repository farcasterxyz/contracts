// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {IdRegistry} from "../src/IdRegistry.sol";
import {StorageRent} from "../src/StorageRent.sol";

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

contract StorageRentHarness is StorageRent {
    constructor(
        AggregatorV3Interface _priceFeed,
        AggregatorV3Interface _uptimeFeed,
        uint256 _rentalPeriod,
        uint256 _usdUnitPrice,
        uint256 _maxUnits,
        address _vault,
        address _roleAdmin,
        address _admin,
        address _operator,
        address _treasurer
    )
        StorageRent(
            _priceFeed,
            _uptimeFeed,
            _rentalPeriod,
            _usdUnitPrice,
            _maxUnits,
            _vault,
            _roleAdmin,
            _admin,
            _operator,
            _treasurer
        )
    {}

    function adminRoleId() external pure returns (bytes32) {
        return ADMIN_ROLE;
    }

    function operatorRoleId() external pure returns (bytes32) {
        return OPERATOR_ROLE;
    }

    function treasurerRoleId() external pure returns (bytes32) {
        return TREASURER_ROLE;
    }
}

contract MockChainlinkFeed is AggregatorV3Interface {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 timeStamp;
        uint80 answeredInRound;
    }

    RoundData public roundData;

    uint8 public decimals;
    string public description;
    uint256 public version = 1;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
    }

    function setAnswer(int256 value) external {
        roundData.answer = value;
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

contract MockPriceFeed is MockChainlinkFeed(8, "Mock ETH/USD Price Feed") {
    function setPrice(int256 _price) external {
        roundData.answer = _price;
    }
}

contract MockUptimeFeed is MockChainlinkFeed(0, "Mock L2 Sequencer Uptime Feed") {}

contract RevertOnReceive {
    receive() external payable {
        revert("Cannot receive ETH");
    }
}
