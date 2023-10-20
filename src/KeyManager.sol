// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {Nonces} from "openzeppelin-latest/contracts/utils/Nonces.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {IKeyManager} from "./interfaces/IKeyManager.sol";
import {IStorageRegistry} from "./interfaces/IStorageRegistry.sol";
import {IKeyRegistry} from "./interfaces/IKeyRegistry.sol";
import {IMetadataValidator} from "./interfaces/IMetadataValidator.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Signatures} from "./lib/Signatures.sol";
import {TrustedCaller} from "./lib/TrustedCaller.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";

/**
 * @title Farcaster KeyManager
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract KeyManager is IKeyManager, Ownable2Step, Signatures, Pausable, EIP712, Nonces {
    using FixedPointMathLib for uint256;
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller provides the wrong payment amount.
    error InvalidPayment();

    /// @dev Revert if transferred to the zero address.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the contract owner sets the usdFee
     *
     * @param oldFee The previous fee. Fixed point value with 8 decimals
     * @param newFee The new fee. Fixed point value with 8 decimals
     */
    event SetUsdFee(uint256 oldFee, uint256 newFee);

    /**
     * @dev Emit an event when an owner changes the vault.
     *
     * @param oldVault The previous vault.
     * @param newVault The new vault.
     */
    event SetVault(address oldVault, address newVault);

    /**
     * @dev Emit an event when the owner withdraws any contract balance to the vault.
     *
     * @param to     Address of recipient.
     * @param amount The amount of ether withdrawn.
     */
    event Withdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyManager
     */
    string public constant VERSION = "2023.10.04";

    /**
     * @inheritdoc IKeyManager
     */
    bytes32 public constant ADD_TYPEHASH = keccak256(
        "Add(address owner,uint32 keyType,bytes key,uint8 metadataType,bytes metadata,uint256 nonce,uint256 deadline)"
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyManager
     */
    IKeyRegistry public keyRegistry;

    /**
     * @inheritdoc IKeyManager
     */
    IStorageRegistry public storageRegistry;

    /**
     * @inheritdoc IKeyManager
     */
    uint256 public usdFee;

    /**
     * @inheritdoc IKeyManager
     */
    address public vault;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _keyRegistry,
        address _storageRegistry,
        address _initialOwner,
        address _initialVault,
        uint256 _initialUsdFee
    ) EIP712("Farcaster KeyManager", "1") {
        keyRegistry = IKeyRegistry(_keyRegistry);
        storageRegistry = IStorageRegistry(_storageRegistry);

        usdFee = _initialUsdFee;
        emit SetUsdFee(0, _initialUsdFee);

        vault = _initialVault;
        emit SetVault(address(0), _initialVault);

        _transferOwnership(_initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyManager
     */
    function price() public view returns (uint256) {
        return usdFee.divWadUp(_ethUsdPrice());
    }

    /*//////////////////////////////////////////////////////////////
                              REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyManager
     */
    function add(
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata
    ) external payable whenNotPaused returns (uint256 overpayment) {
        uint256 fee = price();
        if (msg.value < fee) revert InvalidPayment();

        keyRegistry.add(msg.sender, keyType, key, metadataType, metadata);

        overpayment = msg.value - fee;
        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /**
     * @inheritdoc IKeyManager
     */
    function addFor(
        address fidOwner,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint256 deadline,
        bytes calldata sig
    ) external payable whenNotPaused returns (uint256 overpayment) {
        uint256 fee = price();
        if (msg.value < fee) revert InvalidPayment();

        _verifyAddSig(fidOwner, keyType, key, metadataType, metadata, deadline, sig);
        keyRegistry.add(fidOwner, keyType, key, metadataType, metadata);

        overpayment = msg.value - fee;
        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE FEED
    //////////////////////////////////////////////////////////////*/

    function _ethUsdPrice() internal view returns (uint256) {
        uint256 fixedEthUsdPrice = storageRegistry.fixedEthUsdPrice();
        if (fixedEthUsdPrice != 0) return fixedEthUsdPrice;
        return storageRegistry.ethUsdPrice();
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyManager
     */
    function setUsdFee(uint256 _usdFee) external onlyOwner {
        emit SetUsdFee(usdFee, _usdFee);
        usdFee = _usdFee;
    }

    /**
     * @inheritdoc IKeyManager
     */
    function setVault(address vaultAddr) external onlyOwner {
        if (vaultAddr == address(0)) revert InvalidAddress();
        emit SetVault(vault, vaultAddr);
        vault = vaultAddr;
    }

    /**
     * @inheritdoc IKeyManager
     */
    function withdraw(uint256 amount) external onlyOwner {
        emit Withdraw(vault, amount);
        vault.sendNative(amount);
    }

    /**
     * @inheritdoc IKeyManager
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc IKeyManager
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifyAddSig(
        address fidOwner,
        uint32 keyType,
        bytes memory key,
        uint8 metadataType,
        bytes memory metadata,
        uint256 deadline,
        bytes memory sig
    ) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        ADD_TYPEHASH,
                        fidOwner,
                        keyType,
                        keccak256(key),
                        metadataType,
                        keccak256(metadata),
                        _useNonce(fidOwner),
                        deadline
                    )
                )
            ),
            fidOwner,
            deadline,
            sig
        );
    }
}
