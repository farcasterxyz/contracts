// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IBundlerV1} from "./interfaces/IBundlerV1.sol";
import {IIdGateway} from "./interfaces/IIdGateway.sol";
import {IKeyGateway} from "./interfaces/IKeyGateway.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

/**
 * @title Farcaster Bundler
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract BundlerV1 is IBundlerV1 {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBundlerV1
     */
    string public constant VERSION = "2023.11.15";

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBundlerV1
     */
    IIdGateway public immutable idGateway;

    /**
     * @inheritdoc IBundlerV1
     */
    IKeyGateway public immutable keyGateway;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the addresses of the IdGateway and KeyGateway contracts.
     *
     * @param _idGateway       Address of the IdGateway contract
     * @param _keyGateway      Address of the KeyGateway contract
     */
    constructor(address _idGateway, address _keyGateway) {
        idGateway = IIdGateway(payable(_idGateway));
        keyGateway = IKeyGateway(payable(_keyGateway));
    }

    /**
     * @inheritdoc IBundlerV1
     */
    function price(
        uint256 extraStorage
    ) external view returns (uint256) {
        return idGateway.price(extraStorage);
    }

    /**
     * @inheritdoc IBundlerV1
     */
    function register(
        RegistrationParams calldata registerParams,
        SignerParams[] calldata signerParams,
        uint256 extraStorage
    ) external payable returns (uint256) {
        (uint256 fid, uint256 overpayment) = idGateway.registerFor{value: msg.value}(
            registerParams.to, registerParams.recovery, registerParams.deadline, registerParams.sig, extraStorage
        );

        uint256 signersLen = signerParams.length;
        for (uint256 i; i < signersLen;) {
            SignerParams calldata signer = signerParams[i];
            keyGateway.addFor(
                registerParams.to,
                signer.keyType,
                signer.key,
                signer.metadataType,
                signer.metadata,
                signer.deadline,
                signer.sig
            );

            // Safety: i can be incremented unchecked since it is bound by signerParams.length.
            unchecked {
                ++i;
            }
        }
        if (overpayment > 0) msg.sender.sendNative(overpayment);
        return fid;
    }

    receive() external payable {
        if (msg.sender != address(idGateway)) revert Unauthorized();
    }
}
