// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Registration} from "./Registration.sol";
import {StorageRegistry} from "./StorageRegistry.sol";
import {KeyRegistry} from "./KeyRegistry.sol";
import {IBundler} from "./interfaces/IBundler.sol";
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

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Contract version specified using Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.08.23";

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Address of the Registration contract
     */
    Registration public immutable registration;

    /**
     * @dev Address of the StorageRegistry contract
     */
    StorageRegistry public immutable storageRegistry;

    /**
     * @dev Address of the KeyRegistry contract
     */
    KeyRegistry public immutable keyRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the addresses of the Registry contracts and the trusted caller, which is
     *         allowed to register users during the bootstrap phase.
     *
     * @param _registration    Address of the Registration contract
     * @param _storageRegistry Address of the StorageRegistry contract
     * @param _keyRegistry     Address of the KeyRegistry contract
     * @param _trustedCaller   Address that can call trustedRegister and trustedBatchRegister
     * @param _initialOwner    Address that can set the trusted caller
     */
    constructor(
        address _registration,
        address _storageRegistry,
        address _keyRegistry,
        address _trustedCaller,
        address _initialOwner
    ) TrustedCaller(_initialOwner) {
        registration = Registration(payable(_registration));
        storageRegistry = StorageRegistry(_storageRegistry);
        keyRegistry = KeyRegistry(_keyRegistry);
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Register an fid, multiple signers, and rent storage to an address in a single transaction.
     *
     * @param registrationParams Struct containing registration parameters: to, recovery, deadline, and signature.
     * @param signerParams      Array of structs containing signer parameters: keyType, key, metadataType,
     *                        metadata, deadline, and signature.
     * @param extraStorage Number of additional storage units to rent
     *
     */
    function register(
        RegistrationParams calldata registrationParams,
        SignerParams[] calldata signerParams,
        uint256 extraStorage
    ) external payable {
        (uint256 fid, uint256 balance) = registration.registerFor{value: msg.value}(
            registrationParams.to, registrationParams.recovery, registrationParams.deadline, registrationParams.sig
        );

        uint256 signersLen = signerParams.length;
        for (uint256 i; i < signersLen;) {
            SignerParams calldata signer = signerParams[i];
            keyRegistry.addFor(
                registrationParams.to,
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
            uint256 overpayment = storageRegistry.rent{value: balance}(fid, extraStorage);
            if (overpayment > 0) {
                msg.sender.sendNative(overpayment);
            }
        }
    }

    /**
     * @notice Register an fid, add a signer, and credit storage to an address in a single transaction. Can only
     *         be called by the trustedCaller during the Seedable phase.
     *
     * @param user UserData struct including to/recovery address, key params, and number of storage units.
     */
    function trustedRegister(UserData calldata user) external onlyTrustedCaller {
        // Will revert unless IdRegistry is in the Seedable phase
        uint256 fid = registration.trustedRegister(user.to, user.recovery);
        uint256 signersLen = user.signers.length;
        for (uint256 i; i < signersLen;) {
            SignerData calldata signer = user.signers[i];
            keyRegistry.trustedAdd(user.to, signer.keyType, signer.key, signer.metadataType, signer.metadata);
            unchecked {
                ++i;
            }
        }
        storageRegistry.credit(fid, user.units);
    }

    /**
     * @notice Register fids, keys, and credit storage for multiple users in a single transaction. Can
     *         only be called by the trustedCaller during the Seedable phase. Will be used when
     *         migrating across Ethereum networks to bootstrap a new contract with existing data.
     *
     * @param users  Array of UserData structs to register
     */
    function trustedBatchRegister(UserData[] calldata users) external onlyTrustedCaller {
        // Safety: calls inside a loop are safe since caller is trusted
        uint256 usersLen = users.length;
        for (uint256 i; i < usersLen;) {
            UserData calldata user = users[i];
            uint256 fid = registration.trustedRegister(user.to, user.recovery);
            uint256 signersLen = user.signers.length;

            for (uint256 j; j < signersLen;) {
                SignerData calldata signer = user.signers[j];
                keyRegistry.trustedAdd(user.to, signer.keyType, signer.key, signer.metadataType, signer.metadata);
                unchecked {
                    ++j;
                }
            }

            storageRegistry.credit(fid, user.units);

            // We know this will not overflow because it's less than the length of the array, which is a `uint256`.
            unchecked {
                ++i;
            }
        }
    }

    receive() external payable {
        if (msg.sender != address(storageRegistry) && msg.sender != address(registration)) revert Unauthorized();
    }
}
