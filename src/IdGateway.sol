// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IIdGateway} from "./interfaces/IIdGateway.sol";
import {IStorageRegistry} from "./interfaces/IStorageRegistry.sol";
import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {TrustedCaller} from "./lib/TrustedCaller.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Nonces} from "./lib/Nonces.sol";
import {Signatures} from "./lib/Signatures.sol";

/**
 * @title Farcaster IdGateway
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract IdGateway is IIdGateway, TrustedCaller, Signatures, EIP712, Nonces {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdGateway
     */
    string public constant VERSION = "2023.10.04";

    /**
     * @inheritdoc IIdGateway
     */
    bytes32 public constant REGISTER_TYPEHASH =
        keccak256("Register(address to,address recovery,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdGateway
     */
    IIdRegistry public immutable idRegistry;

    /**
     * @inheritdoc IIdGateway
     */
    IStorageRegistry public immutable storageRegistry;

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
    ) TrustedCaller(_initialOwner) EIP712("Farcaster IdGateway", "1") {
        idRegistry = IIdRegistry(_idRegistry);
        storageRegistry = IStorageRegistry(_storageRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                             PRICE VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the total price to register, equal to 1
     *         storage unit.
     *
     * @return Total price in wei.
     */
    function price() external view returns (uint256) {
        return storageRegistry.unitPrice();
    }

    function price(uint256 extraStorage) external view returns (uint256) {
        return storageRegistry.price(1 + extraStorage);
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdGateway
     */
    function register(address recovery) external payable returns (uint256, uint256) {
        return register(recovery, 0);
    }

    function register(
        address recovery,
        uint256 extraStorage
    ) public payable whenNotPaused whenNotTrusted returns (uint256 fid, uint256 overpayment) {
        fid = idRegistry.register(msg.sender, recovery);
        overpayment = _rentStorage(fid, extraStorage, msg.value, msg.sender);
    }

    /**
     * @inheritdoc IIdGateway
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external payable returns (uint256, uint256) {
        return registerFor(to, recovery, deadline, sig, 0);
    }

    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig,
        uint256 extraStorage
    ) public payable whenNotPaused whenNotTrusted returns (uint256 fid, uint256 overpayment) {
        /* Revert if signature is invalid */
        _verifyRegisterSig({to: to, recovery: recovery, deadline: deadline, sig: sig});
        fid = idRegistry.register(to, recovery);
        overpayment = _rentStorage(fid, extraStorage, msg.value, msg.sender);
    }

    /**
     * @inheritdoc IIdGateway
     */
    function trustedRegister(
        address to,
        address recovery
    ) external onlyTrustedCaller whenNotPaused returns (uint256 fid) {
        fid = idRegistry.register(to, recovery);
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

    function _rentStorage(
        uint256 fid,
        uint256 extraUnits,
        uint256 payment,
        address payer
    ) internal returns (uint256 overpayment) {
        overpayment = storageRegistry.rent{value: payment}(fid, 1 + extraUnits);

        if (overpayment > 0) {
            payer.sendNative(overpayment);
        }
    }

    receive() external payable {
        if (msg.sender != address(storageRegistry)) revert Unauthorized();
    }
}
