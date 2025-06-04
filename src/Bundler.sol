// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IBundler} from "./interfaces/IBundler.sol";
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
contract Bundler is IBundler {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBundler
     */
    string public constant VERSION = "2025.06.16";

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBundler
     */
    IIdGateway public immutable idGateway;

    /**
     * @inheritdoc IBundler
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
     * @inheritdoc IBundler
     */
    function price(
        uint256 extraStorage
    ) external view returns (uint256) {
        return idGateway.price(extraStorage);
    }

    /**
     * @inheritdoc IBundler
     */
    function register(
        RegistrationParams calldata registerParams,
        SignerParams[] calldata signerParams,
        uint256 extraStorage
    ) external payable returns (uint256) {
        (uint256 fid, uint256 overpayment) = idGateway.registerFor{value: msg.value}(
            registerParams.to, registerParams.recovery, registerParams.deadline, registerParams.sig, extraStorage
        );
        _addKeys(registerParams.to, signerParams);
        if (overpayment > 0) msg.sender.sendNative(overpayment);
        return fid;
    }

    /**
     * @inheritdoc IBundler
     */
    function addKeys(address fidOwner, SignerParams[] calldata signerParams) external {
        _addKeys(fidOwner, signerParams);
    }

    function _addKeys(address fidOwner, SignerParams[] calldata signerParams) internal {
        uint256 signersLen = signerParams.length;
        for (uint256 i; i < signersLen; ++i) {
            SignerParams calldata signer = signerParams[i];
            keyGateway.addFor(
                fidOwner, signer.keyType, signer.key, signer.metadataType, signer.metadata, signer.deadline, signer.sig
            );
        }
    }

    receive() external payable {
        if (msg.sender != address(idGateway)) revert Unauthorized();
    }
}
