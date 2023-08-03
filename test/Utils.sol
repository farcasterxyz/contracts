// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {FnameResolver} from "../src/FnameResolver.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";
import {StorageRegistry} from "../src/StorageRegistry.sol";
import {Bundler} from "../src/Bundler.sol";

/* solhint-disable no-empty-blocks */

contract BundlerHarness is Bundler {
    constructor(
        address _idRegistry,
        address _storageRegistry,
        address _keyRegistry,
        address _trustedCaller,
        address _owner
    ) Bundler(_idRegistry, _storageRegistry, _keyRegistry, _trustedCaller, _owner) {}
}

contract FnameResolverHarness is FnameResolver {
    constructor(string memory _url, address _signer, address _owner) FnameResolver(_url, _signer, _owner) {}

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
    constructor(address owner) IdRegistry(owner) {}

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
    constructor(
        address _idRegistry,
        uint24 _gracePeriod,
        address _owner
    ) KeyRegistry(_idRegistry, _gracePeriod, _owner) {}

    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function addTypehash() public pure returns (bytes32) {
        return _ADD_TYPEHASH;
    }

    function removeTypehash() public pure returns (bytes32) {
        return _REMOVE_TYPEHASH;
    }
}

contract StorageRegistryHarness is StorageRegistry {
    constructor(
        AggregatorV3Interface _priceFeed,
        AggregatorV3Interface _uptimeFeed,
        uint256 _usdUnitPrice,
        uint256 _maxUnits,
        address _vault,
        address _roleAdmin,
        address _owner,
        address _operator,
        address _treasurer
    )
        StorageRegistry(
            _priceFeed,
            _uptimeFeed,
            _usdUnitPrice,
            _maxUnits,
            _vault,
            _roleAdmin,
            _owner,
            _operator,
            _treasurer
        )
    {}

    function ownerRoleId() external pure returns (bytes32) {
        return OWNER_ROLE;
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
    bool public stubTimeStamp;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setStubTimeStamp(bool _stubTimeStamp) external {
        stubTimeStamp = _stubTimeStamp;
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
        return (
            roundData.roundId,
            roundData.answer,
            roundData.startedAt,
            stubTimeStamp ? roundData.timeStamp : block.timestamp,
            roundData.answeredInRound
        );
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
