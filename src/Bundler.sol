// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IdManager} from "./IdManager.sol";
import {StorageRegistry} from "./StorageRegistry.sol";
import {KeyRegistry} from "./KeyRegistry.sol";
import {KeyManager} from "./KeyManager.sol";
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
    string public constant VERSION = "2023.10.04";

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Address of the IdManager contract
     */
    IdManager public immutable idManager;

    /**
     * @dev Address of the KeyManager contract
     */
    KeyManager public immutable keyManager;

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
     * @notice Configure the addresses of the Manager and Registry contracts
     *         and the trusted caller, which is allowed to register users
     *         during the bootstrap phase.
     *
     * @param _idManager       Address of the IdManager contract
     * @param _storageRegistry Address of the StorageRegistry contract
     * @param _keyManager      Address of the KeyRegistry contract
     * @param _trustedCaller   Address that can call trustedRegister and trustedBatchRegister
     * @param _initialOwner    Address that can set the trusted caller
     */
    constructor(
        address _idManager,
        address _keyManager,
        address _storageRegistry,
        address _keyRegistry,
        address _trustedCaller,
        address _initialOwner
    ) TrustedCaller(_initialOwner) {
        idManager = IdManager(payable(_idManager));
        keyManager = KeyManager(payable(_keyManager));
        storageRegistry = StorageRegistry(_storageRegistry);
        keyRegistry = KeyRegistry(_keyRegistry);
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Calculate the total price of a registration.
     *
     * @param signers      Number of signers to add.
     * @param extraStorage Number of additional storage units to rent.
     *
     */
    function price(uint256 signers, uint256 extraStorage) external view returns (uint256) {
        return keyManager.fee() * signers + storageRegistry.price(1 + extraStorage);
    }

    /**
     * @notice Register an fid, add one or more signers, and rent storage in a single transaction.
     *
     * @param registerParams Struct containing register parameters: to, recovery, deadline, and signature.
     * @param signerParams   Array of structs containing signer parameters: keyType, key, metadataType,
     *                       metadata, deadline, and signature.
     * @param extraStorage   Number of additional storage units to rent. (FID registration includes 1 unit).
     *
     */
    function register(
        RegistrationParams calldata registerParams,
        SignerParams[] calldata signerParams,
        uint256 extraStorage
    ) external payable {
        (uint256 fid, uint256 balance) = idManager.registerFor{value: msg.value}(
            registerParams.to, registerParams.recovery, registerParams.deadline, registerParams.sig
        );

        uint256 signersLen = signerParams.length;
        for (uint256 i; i < signersLen;) {
            SignerParams calldata signer = signerParams[i];
            balance = keyManager.addFor{value: balance}(
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
            balance = storageRegistry.rent{value: balance}(fid, extraStorage);
        }
        if (balance > 0) {
            msg.sender.sendNative(balance);
        }
    }

    /**
     * @notice Register fids for multiple users in a single transaction. Can only be called by the trustedCaller
     *         during the Seedable phase. Will be used when migrating across Ethereum networks to bootstrap a new
     *         contract with existing data.
     *
     * @param users  Array of UserData structs to register
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
