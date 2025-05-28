// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {AccessControlEnumerable} from "openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITierRegistry} from "./interfaces/ITierRegistry.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

/**
 * @title Farcaster StorageRegistry
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract TierRegistry is ITierRegistry, AccessControlEnumerable, Pausable {
    using FixedPointMathLib for uint256;
    using TransferHelper for address;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller attempts to rent storage after the contract is deprecated.
    error ContractDeprecated();

    /// @dev Revert if the caller attempts to rent zero units.
    error InvalidAmount();

    error InvalidTier();

    error InvalidPrice();

    error InvalidBatchInput();

    error InvalidAddress();

    /// @dev Revert if the caller is not an owner.
    error NotOwner();

    /// @dev Revert if the caller is not an operator.
    error NotOperator();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // TODO(aditi): Maybe rename without Purchase in name
    event PurchasedTier(uint256 indexed fid, uint256 tier, uint256 forDays);

    /**
     * @dev Emit an event when an owner changes the vault.
     *
     * @param oldVault The previous vault.
     * @param newVault The new vault.
     */
    event SetVault(address oldVault, address newVault);

    event SetToken(address oldToken, address newToken);

    event SetTierPrice(uint256 tier, address token, uint256 oldPrice, uint256 newPrice);

    event RemoveTier(uint256 tier);

    event SetMinDays(uint256 oldMinDays, uint256 newMinDays);

    event SetMaxDays(uint256 oldMaxDays, uint256 newMaxDays);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    string public constant VERSION = "2025.05.21";
    // TODO(aditi): Update the date

    bytes32 internal constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    uint256 public minDays;
    uint256 public maxDays;
    address public vault;
    address public paymentToken;
    uint256[] public validTiers;

    // Keep tier a number not enum so we don't need to ugrade contract to add a new one.
    mapping(uint256 => uint256) public tokenPricePerDay;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the price feed, uptime feed, and initial parameters.
     *
     * @param _initialVault                  Initial vault address.
     * @param _initialRoleAdmin              Initial role admin address.
     * @param _initialOwner                  Initial owner address.
     * @param _initialOperator               Initial operator address.
     */
    constructor(
        address _initialToken,
        address _initialVault,
        address _initialRoleAdmin,
        address _initialOwner,
        address _initialOperator,
        uint256 _initialMinDays,
        uint256 _initialMaxDays
    ) {
        vault = _initialVault;
        emit SetVault(address(0), _initialVault);

        paymentToken = _initialToken;
        emit SetToken(address(0), _initialToken);

        minDays = _initialMinDays;
        emit SetMinDays(0, minDays);

        maxDays = _initialMaxDays;
        emit SetMaxDays(0, maxDays);

        _grantRole(DEFAULT_ADMIN_ROLE, _initialRoleAdmin);
        _grantRole(OWNER_ROLE, _initialOwner);
        _grantRole(OPERATOR_ROLE, _initialOperator);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (!hasRole(OWNER_ROLE, msg.sender)) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE RENTAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    function purchaseTier(uint256 fid, uint256 tier, uint256 forDays, address payer) external whenNotPaused {
        uint256 pricePerDay = tokenPricePerDay[tier];
        if (forDays == 0) revert InvalidAmount();
        if (pricePerDay == 0) revert InvalidTier();
        if (forDays < minDays) revert InvalidAmount();
        if (forDays > maxDays) revert InvalidAmount();

        uint256 cost = pricePerDay * forDays;

        emit PurchasedTier(fid, tier, forDays);

        IERC20 token = IERC20(paymentToken);
        token.safeTransferFrom(payer, vault, cost);
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function batchPurchaseTiers(
        uint256[] calldata fids,
        uint256[] calldata tiers,
        uint256[] calldata forDays,
        address payer
    ) external whenNotPaused {
        if (fids.length == 0) revert InvalidBatchInput();
        if (fids.length != tiers.length) revert InvalidBatchInput();
        if (fids.length != forDays.length) revert InvalidBatchInput();

        // Effects
        uint256 totalCost;
        for (uint256 i; i < fids.length; ++i) {
            uint256 pricePerDay = tokenPricePerDay[tiers[i]];
            uint256 numDays = forDays[i];
            if (numDays == 0) revert InvalidAmount();
            if (pricePerDay == 0) revert InvalidTier();
            if (numDays < minDays) revert InvalidAmount();
            if (numDays > maxDays) revert InvalidAmount();
            totalCost += pricePerDay * numDays;
        }

        for (uint256 i; i < fids.length; ++i) {
            emit PurchasedTier(fids[i], tiers[i], forDays[i]);
        }

        IERC20 token = IERC20(paymentToken);
        token.safeTransferFrom(payer, vault, totalCost);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITierRegistry
     */
    function creditTier(uint256 fid, uint256 tier, uint256 forDays) external onlyOperator whenNotPaused {
        if (forDays == 0) revert InvalidAmount();
        if (tokenPricePerDay[tier] == 0) revert InvalidTier();
        if (forDays < minDays) revert InvalidAmount();
        if (forDays > maxDays) revert InvalidAmount();

        emit PurchasedTier(fid, tier, forDays);
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function batchCreditTiers(
        uint256[] calldata fids,
        uint256[] calldata tiers,
        uint256[] calldata forDays
    ) external onlyOperator whenNotPaused {
        // Pre-checks
        if (fids.length == 0) revert InvalidBatchInput();
        if (fids.length != tiers.length) revert InvalidBatchInput();
        if (fids.length != forDays.length) revert InvalidBatchInput();

        for (uint256 i; i < fids.length; ++i) {
            if (forDays[i] == 0) revert InvalidAmount();
            if (tokenPricePerDay[tiers[i]] == 0) revert InvalidTier();
            if (forDays[i] < minDays) revert InvalidAmount();
            if (forDays[i] > maxDays) revert InvalidAmount();
        }

        for (uint256 i; i < fids.length; ++i) {
            emit PurchasedTier(fids[i], tiers[i], forDays[i]);
        }
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function setVault(
        address vaultAddr
    ) external onlyOwner {
        if (vaultAddr == address(0)) revert InvalidAddress();
        emit SetVault(vault, vaultAddr);
        vault = vaultAddr;
    }

    function setToken(
        address tokenAddr
    ) external onlyOwner {
        if (tokenAddr == address(0)) revert InvalidAddress();
        // Delete prices for old token
        for (uint256 i; i < validTiers.length; ++i) {
            delete tokenPricePerDay[validTiers[i]];
        }
        emit SetToken(paymentToken, tokenAddr);
        paymentToken = tokenAddr;
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function setTier(uint256 tier, uint256 price) external onlyOwner {
        emit SetTierPrice(tier, paymentToken, tokenPricePerDay[tier], price);
        tokenPricePerDay[tier] = price;

        for (uint256 i; i < validTiers.length; ++i) {
            if (validTiers[i] == tier) {
                return;
            }
        }

        validTiers.push(tier);
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function removeTier(
        uint256 tier
    ) external onlyOwner {
        if (tokenPricePerDay[tier] == 0) revert InvalidTier();
        emit RemoveTier(tier);
        delete tokenPricePerDay[tier];
        for (uint256 i; i < validTiers.length; ++i) {
            if (validTiers[i] == tier) {
                validTiers[i] = validTiers[validTiers.length - 1];
                validTiers.pop();
                break;
            }
        }
    }

    function setMinDays(
        uint256 numDays
    ) external onlyOwner {
        if (numDays == 0) revert InvalidAmount();
        emit SetMinDays(minDays, numDays);
        minDays = numDays;
    }

    function setMaxDays(
        uint256 numDays
    ) external onlyOwner {
        if (numDays == 0) revert InvalidAmount();
        emit SetMaxDays(maxDays, numDays);
        maxDays = numDays;
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc ITierRegistry
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
