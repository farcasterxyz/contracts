// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

import {FnameResolver} from "../src/FnameResolver.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {KeyRegistry} from "../src/KeyRegistry.sol";
import {StorageRegistry} from "../src/StorageRegistry.sol";
import {SignedKeyRequestValidator} from "../src/validators/SignedKeyRequestValidator.sol";
import {BundlerV1} from "../src/BundlerV1.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC1271} from "openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/* solhint-disable no-empty-blocks */

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

contract StubValidator {
    bool isValid = true;

    function validate(
        uint256, /* userFid */
        bytes memory, /* signerPubKey */
        bytes memory /* appIdBytes */
    ) external view returns (bool) {
        return isValid;
    }

    function setIsValid(
        bool val
    ) external {
        isValid = val;
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

    function setShouldRevert(
        bool _shouldRevert
    ) external {
        shouldRevert = _shouldRevert;
    }

    function setStubTimeStamp(
        bool _stubTimeStamp
    ) external {
        stubTimeStamp = _stubTimeStamp;
    }

    function setAnswer(
        int256 value
    ) external {
        roundData.answer = value;
    }

    function setRoundData(
        RoundData calldata _roundData
    ) external {
        roundData = _roundData;
    }

    function getRoundData(
        uint80
    ) external view returns (uint80, int256, uint256, uint256, uint80) {
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
    function setPrice(
        int256 _price
    ) external {
        roundData.answer = _price;
    }
}

contract MockUptimeFeed is MockChainlinkFeed(0, "Mock L2 Sequencer Uptime Feed") {}

contract RevertOnReceive {
    receive() external payable {
        revert("Cannot receive ETH");
    }
}

/*//////////////////////////////////////////////////////////////
                     SMART CONTRACT WALLET MOCKS
//////////////////////////////////////////////////////////////*/

contract ERC1271WalletMock is Ownable, IERC1271 {
    constructor(
        address owner
    ) {
        super.transferOwnership(owner);
    }

    function isValidSignature(bytes32 hash, bytes memory signature) public view returns (bytes4 magicValue) {
        return
            SignatureChecker.isValidSignatureNow(owner(), hash, signature) ? this.isValidSignature.selector : bytes4(0);
    }
}

contract ERC1271MaliciousMockForceRevert is Ownable, IERC1271 {
    bool internal _forceRevert = true;

    constructor(
        address owner
    ) {
        super.transferOwnership(owner);
    }

    function setForceRevert(
        bool forceRevert
    ) external {
        _forceRevert = forceRevert;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) public view returns (bytes4) {
        if (_forceRevert) {
            assembly {
                mstore(0, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
                return(0, 32)
            }
        }

        return
            SignatureChecker.isValidSignatureNow(owner(), hash, signature) ? this.isValidSignature.selector : bytes4(0);
    }
}
