// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IBundler} from "./interfaces/IBundler.sol";
import {IIdManager} from "./interfaces/IIdManager.sol";
import {IKeyManager} from "./interfaces/IKeyManager.sol";
import {IStorageRegistry} from "./interfaces/IStorageRegistry.sol";
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
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller provides the wrong payment amount.
    error InvalidPayment();

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

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
    IIdManager public immutable idManager;

    /**
     * @inheritdoc IBundler
     */
    IKeyManager public immutable keyManager;

    /**
     * @inheritdoc IBundler
     */
    IStorageRegistry public immutable storageRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the addresses of the Manager and Registry contracts
     *         and the trusted caller, which is allowed to register users
     *         during the bootstrap phase.
     *
     * @param _idManager       Address of the IdManager contract
     * @param _keyManager      Address of the KeyManager contract
     * @param _storageRegistry Address of the StorageRegistry contract
     * @param _trustedCaller   Address that can call trustedRegister and trustedBatchRegister
     * @param _initialOwner    Address that can set the trusted caller
     */
    constructor(
        address _idManager,
        address _keyManager,
        address _storageRegistry,
        address _trustedCaller,
        address _initialOwner
    ) TrustedCaller(_initialOwner) {
        idManager = IIdManager(payable(_idManager));
        keyManager = IKeyManager(payable(_keyManager));
        storageRegistry = IStorageRegistry(_storageRegistry);
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @inheritdoc IBundler
     */
    function price(uint256 signers, uint256 extraStorage) external view returns (uint256) {
        return keyManager.price() * signers + idManager.price() + storageRegistry.price(extraStorage);
    }

    /**
     * @inheritdoc IBundler
     */
    function register(
        RegistrationParams calldata registerParams,
        SignerParams[] calldata signerParams,
        uint256 extraStorage
    ) external payable {
        uint256 registerFee = idManager.price();
        uint256 signerFee = keyManager.price();
        uint256 storageFee = storageRegistry.price(extraStorage);
        uint256 totalFee = registerFee + signerFee * signerParams.length + storageFee;

        if (msg.value < totalFee) revert InvalidPayment();
        uint256 overpayment = msg.value - totalFee;

        (uint256 fid,) = idManager.registerFor{value: registerFee}(
            registerParams.to, registerParams.recovery, registerParams.deadline, registerParams.sig
        );

        uint256 signersLen = signerParams.length;
        for (uint256 i; i < signersLen;) {
            SignerParams calldata signer = signerParams[i];
            keyManager.addFor{value: signerFee}(
                registerParams.to,
                signer.keyType,
                signer.key,
                signer.metadataType,
                signer.metadata,
                signer.deadline,
                signer.sig
            );

            // We know this will not overflow because it's less than the length of the array, which is a `uint256`.
            unchecked {
                ++i;
            }
        }

        if (extraStorage > 0) {
            storageRegistry.rent{value: storageFee}(fid, extraStorage);
        }
        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /**
     * @inheritdoc IBundler
     */
    function trustedBatchRegister(UserData[] calldata users) external onlyTrustedCaller {
        // Safety: calls inside a loop are safe since caller is trusted
        uint256 usersLen = users.length;
        for (uint256 i; i < usersLen;) {
            UserData calldata user = users[i];
            idManager.trustedRegister(user.to, user.recovery);
            unchecked {
                ++i;
            }
        }
    }

    receive() external payable {
        if (
            msg.sender != address(storageRegistry) && msg.sender != address(idManager)
                && msg.sender != address(keyManager)
        ) revert Unauthorized();
    }
}
