// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IIdGatewayV2} from "./interfaces/IIdGatewayV2.sol";
import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {Guardians} from "./abstract/Guardians.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {EIP712} from "./abstract/EIP712.sol";
import {Nonces} from "./abstract/Nonces.sol";
import {Signatures} from "./abstract/Signatures.sol";

/**
 * @title Farcaster IdGateway
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract IdGatewayV2 is IIdGatewayV2, Guardians, Signatures, EIP712, Nonces {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdGatewayV2
     */
    string public constant VERSION = "2023.11.15";

    /**
     * @inheritdoc IIdGatewayV2
     */
    bytes32 public constant REGISTER_TYPEHASH =
        keccak256("Register(address to,address recovery,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdGatewayV2
     */
    IIdRegistry public immutable idRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure IdRegistry and StorageRegistry addresses.
     *         Set the owner of the contract to the provided _owner.
     *
     * @param _idRegistry      IdRegistry address.
     * @param _initialOwner    Initial owner address.
     *
     */
    constructor(
        address _idRegistry,
        address _initialOwner
    ) Guardians(_initialOwner) EIP712("Farcaster IdGateway", "1") {
        idRegistry = IIdRegistry(_idRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                             PRICE VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdGatewayV2
     */
    function price() public pure returns (uint256) {
        return 1;
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdGatewayV2
     */
    function register(
        address recovery
    ) external payable whenNotPaused returns (uint256 fid, uint256 overpayment) {
        fid = idRegistry.register(msg.sender, recovery);
        overpayment = msg.value - price();
        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /**
     * @inheritdoc IIdGatewayV2
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external payable whenNotPaused returns (uint256 fid, uint256 overpayment) {
        /* Revert if signature is invalid */
        _verifyRegisterSig({to: to, recovery: recovery, deadline: deadline, sig: sig});
        fid = idRegistry.register(to, recovery);
        overpayment = msg.value - price();
        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
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
}
