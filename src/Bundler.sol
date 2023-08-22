// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry} from "./IdRegistry.sol";
import {StorageRegistry} from "./StorageRegistry.sol";
import {KeyRegistry} from "./KeyRegistry.sol";
import {TrustedCaller} from "./lib/TrustedCaller.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";

contract Bundler is TrustedCaller {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

    /// @dev Revert if the caller attempts to rent zero storage units.
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Data needed to trusted register a user with the fid and storage contracts.
    struct UserData {
        address to;
        address recovery;
        SignerData[] signers;
        uint256 units;
    }

    /// @notice Data needed to trusted register a signer with the key registry
    struct SignerData {
        uint32 keyType;
        bytes key;
        uint8 metadataType;
        bytes metadata;
    }

    /// @notice Data needed to register an fid with signature.
    struct RegistrationParams {
        address to;
        address recovery;
        uint256 deadline;
        bytes sig;
    }

    /// @notice Data needed to add a signer with signature.
    struct SignerParams {
        uint32 keyType;
        bytes key;
        uint8 metadataType;
        bytes metadata;
        uint256 deadline;
        bytes sig;
    }

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
     * @dev Address of the IdRegistry contract
     */
    IdRegistry public immutable idRegistry;

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
     *        allowed to register during the bootstrap phase.
     *
     * @param _idRegistry      Address of the IdRegistry contract
     * @param _storageRegistry Address of the StorageRegistry contract
     * @param _keyRegistry     Address of the KeyRegistry contract
     * @param _trustedCaller   Address that can call trustedRegister and trustedBatchRegister
     * @param _initialOwner    Address that can set the trusted caller
     */
    constructor(
        address _idRegistry,
        address _storageRegistry,
        address _keyRegistry,
        address _trustedCaller,
        address _initialOwner
    ) TrustedCaller(_initialOwner) {
        idRegistry = IdRegistry(_idRegistry);
        storageRegistry = StorageRegistry(_storageRegistry);
        keyRegistry = KeyRegistry(_keyRegistry);
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Register an fid, multiple signers, and rent storage to an address in a single transaction.
     *
     * @param registration Struct containing registration parameters: to, recovery, deadline, and signature.
     * @param signers      Array of structs containing signer parameters: keyType, key, metadata, deadline, and signature.
     * @param storageUnits Number of storage units to rent
     *
     */
    function register(
        RegistrationParams calldata registration,
        SignerParams[] calldata signers,
        uint256 storageUnits
    ) external payable {
        if (storageUnits == 0) revert InvalidAmount();
        uint256 fid =
            idRegistry.registerFor(registration.to, registration.recovery, registration.deadline, registration.sig);

        uint256 signersLen = signers.length;
        for (uint256 i; i < signersLen;) {
            SignerParams calldata signer = signers[i];
            keyRegistry.addFor(
                registration.to,
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

        uint256 overpayment = storageRegistry.rent{value: msg.value}(fid, storageUnits);

        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
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
        uint256 fid = idRegistry.trustedRegister(user.to, user.recovery);
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
            uint256 fid = idRegistry.trustedRegister(user.to, user.recovery);
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

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {
        if (msg.sender != address(storageRegistry)) revert Unauthorized();
    }
}
