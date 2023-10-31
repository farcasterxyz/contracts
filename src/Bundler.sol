// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IBundler} from "./interfaces/IBundler.sol";
import {IIdGateway} from "./interfaces/IIdGateway.sol";
import {IKeyGateway} from "./interfaces/IKeyGateway.sol";
import {TrustedCaller} from "./lib/TrustedCaller.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";

/**
 * @title Farcaster Bundler
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract Bundler is IBundler, TrustedCaller {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBundler
     */
    string public constant VERSION = "2023.10.04";

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
     * @notice Configure the addresses of the Manager and Registry contracts
     *         and the trusted caller, which is allowed to register users
     *         during the bootstrap phase.
     *
     * @param _idGateway       Address of the IdGateway contract
     * @param _keyGateway      Address of the KeyGateway contract
     * @param _trustedCaller   Address that can call trustedRegister and trustedBatchRegister
     * @param _initialOwner    Address that can set the trusted caller
     */
    constructor(
        address _idGateway,
        address _keyGateway,
        address _trustedCaller,
        address _initialOwner
    ) TrustedCaller(_initialOwner) {
        idGateway = IIdGateway(payable(_idGateway));
        keyGateway = IKeyGateway(payable(_keyGateway));
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @inheritdoc IBundler
     */
    function price(uint256 extraStorage) external view returns (uint256) {
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

            // Safety: won't overflow because it's less than the length of the array, which is a `uint256`.
            unchecked {
                ++i;
            }
        }

        if (overpayment > 0) msg.sender.sendNative(overpayment);
        return fid;
    }

    /**
     * @inheritdoc IBundler
     */
    function trustedBatchRegister(UserData[] calldata users) external onlyTrustedCaller {
        // Safety: calls inside a loop are safe since caller is trusted
        uint256 usersLen = users.length;
        for (uint256 i; i < usersLen;) {
            UserData calldata user = users[i];
            idGateway.trustedRegister(user.to, user.recovery);
            unchecked {
                ++i;
            }
        }
    }

    receive() external payable {
        if (msg.sender != address(idGateway)) revert Unauthorized();
    }
}
