// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {FnameResolver} from "../src/FnameResolver.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";
import {StorageRent} from "../src/StorageRent.sol";
import {Bundler} from "../src/Bundler.sol";

/* solhint-disable no-empty-blocks */

contract BundlerHarness is Bundler {
    constructor(
        address _idRegistry,
        address _storageRent,
        address _trustedCaller
    ) Bundler(_idRegistry, _storageRent, _trustedCaller) {}
}

contract FnameResolverHarness is FnameResolver {
    constructor(string memory _url, address _signer) FnameResolver(_url, _signer) {}

    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function usernameProofTypehash() public pure returns (bytes32) {
        return _USERNAME_PROOF_TYPEHASH;
    }
}

/**
 * @dev IdRegistryHarness exposes IdRegistry's private methods for test assertions.
 */
contract IdRegistryHarness is IdRegistry {
    constructor() IdRegistry() {}

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

    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function registerTypehash() public pure returns (bytes32) {
        return _REGISTER_TYPEHASH;
    }

    function transferTypehash() public pure returns (bytes32) {
        return _TRANSFER_TYPEHASH;
    }
}

contract KeyRegistryHarness is KeyRegistry {
    constructor(address _idRegistry) KeyRegistry(_idRegistry) {}
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

    bool public shouldRevert;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
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
        if (shouldRevert) revert("MockChainLinkFeed: Call failed");
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
