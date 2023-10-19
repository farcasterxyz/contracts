// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Nonces} from "openzeppelin-latest/contracts/utils/Nonces.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";

import {IIdManager} from "./interfaces/IIdManager.sol";
import {IStorageRegistry} from "./interfaces/IStorageRegistry.sol";
import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {TrustedCaller} from "./lib/TrustedCaller.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Signatures} from "./lib/Signatures.sol";

/**
 * @title Farcaster IdManager
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract IdManager is IIdManager, TrustedCaller, Signatures, Pausable, EIP712, Nonces {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdManager
     */
    string public constant VERSION = "2023.10.04";

    /**
     * @inheritdoc IIdManager
     */
    bytes32 public constant REGISTER_TYPEHASH =
        keccak256("Register(address to,address recovery,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdManager
     */
    IIdRegistry public idRegistry;

    /**
     * @inheritdoc IIdManager
     */
    IStorageRegistry public storageRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the owner of the contract to the provided _owner.
     *
     * @param _initialOwner Initial owner address.
     *
     */
    constructor(
        address _idRegistry,
        address _storageRegistry,
        address _initialOwner
    ) TrustedCaller(_initialOwner) EIP712("Farcaster IdManager", "1") {
        idRegistry = IIdRegistry(_idRegistry);
        storageRegistry = IStorageRegistry(_storageRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdManager
     */
    function register(address recovery)
        external
        payable
        whenNotPaused
        whenNotTrusted
        returns (uint256 fid, uint256 overpayment)
    {
        fid = idRegistry.register(msg.sender, recovery);
        overpayment = _rentStorage(fid, msg.value, msg.sender);
    }

    /**
     * @inheritdoc IIdManager
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external payable whenNotPaused whenNotTrusted returns (uint256 fid, uint256 overpayment) {
        /* Revert if signature is invalid */
        _verifyRegisterSig({to: to, recovery: recovery, deadline: deadline, sig: sig});
        fid = idRegistry.register(to, recovery);
        overpayment = _rentStorage(fid, msg.value, msg.sender);
    }

    /**
     * @inheritdoc IIdManager
     */
    function trustedRegister(
        address to,
        address recovery
    ) external onlyTrustedCaller whenNotPaused returns (uint256 fid) {
        fid = idRegistry.register(to, recovery);
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdManager
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc IIdManager
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifyRegisterSig(address to, address recovery, uint256 deadline, bytes memory sig) internal {
        _verifySig(
            _hashTypedDataV4(keccak256(abi.encode(REGISTER_TYPEHASH, to, recovery, _useNonce(to), deadline))),
            to,
            deadline,
            sig
        );
    }

    /*//////////////////////////////////////////////////////////////
                     STORAGE RENTAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _rentStorage(uint256 fid, uint256 payment, address payer) internal returns (uint256 overpayment) {
        overpayment = storageRegistry.rent{value: payment}(fid, 1);

        if (overpayment > 0) {
            payer.sendNative(overpayment);
        }
    }

    receive() external payable {
        if (msg.sender != address(storageRegistry)) revert Unauthorized();
    }
}
