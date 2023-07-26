// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry} from "./IdRegistry.sol";
import {StorageRent} from "./StorageRent.sol";
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

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Data needed to trusted register a user with the fid and storage contracts.
    struct UserData {
        address to;
        address recovery;
        uint32 scheme;
        bytes key;
        bytes metadata;
        uint256 units;
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
        uint32 scheme;
        bytes key;
        bytes metadata;
        uint256 deadline;
        bytes sig;
    }

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Address of the IdRegistry contract
     */
    IdRegistry public immutable idRegistry;

    /**
     * @dev Address of the StorageRent contract
     */
    StorageRent public immutable storageRent;

    /**
     * @dev Address of the StorageRent contract
     */
    KeyRegistry public immutable keyRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the addresses of the Registry contracts and the trusted caller which is
     *        allowed to register during the bootstrap phase.
     *
     * @param _idRegistry    Address of the IdRegistry contract
     * @param _storageRent   Address of the StorageRent contract
     * @param _trustedCaller Address that can call trustedRegister and trustedBatchRegister
     * @param _owner         Address that can set the trusted caller
     */
    constructor(
        address _idRegistry,
        address _storageRent,
        address _keyRegistry,
        address _trustedCaller,
        address _owner
    ) TrustedCaller(_owner) {
        idRegistry = IdRegistry(_idRegistry);
        storageRent = StorageRent(_storageRent);
        keyRegistry = KeyRegistry(_keyRegistry);
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Register an fid, multiple signers, and rent storage to an address in a single transaction.
     *
     * @param registration Struct containing registration parameters: to, from, deadline, and signature.
     * @param signers      Array of structs containing signer parameters: scheme, key, metadata, deadline, and signature.
     * @param storageUnits Number of storage units to rent
     *
     */
    function register(
        RegistrationParams calldata registration,
        SignerParams[] calldata signers,
        uint256 storageUnits
    ) external payable {
        uint256 fid =
            idRegistry.registerFor(registration.to, registration.recovery, registration.deadline, registration.sig);

        for (uint256 i; i < signers.length; i++) {
            SignerParams calldata signer = signers[i];
            keyRegistry.addFor(registration.to, signer.scheme, signer.key, signer.metadata, signer.deadline, signer.sig);
        }

        uint256 overpayment = storageRent.rent{value: msg.value}(fid, storageUnits);

        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /**
     * @notice Register an fid, add a signer, and credit storage to an address in a single transaction. Can only
     *         be called by the trustedCaller during the Seedable phase.
     *
     * @param to           Address of the fid to register
     * @param recovery     Address that is allowed to perform a recovery
     * @param storageUnits Number of storage units to rent
     */
    function trustedRegister(
        address to,
        address recovery,
        uint32 scheme,
        bytes calldata key,
        bytes calldata metadata,
        uint256 storageUnits
    ) external onlyTrustedCaller {
        // Will revert unless IdRegistry is in the Seedable phase
        uint256 fid = idRegistry.trustedRegister(to, recovery);
        keyRegistry.trustedAdd(to, scheme, key, metadata);
        storageRent.credit(fid, storageUnits);
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
        for (uint256 i = 0; i < users.length; i++) {
            uint256 fid = idRegistry.trustedRegister(users[i].to, users[i].recovery);
            keyRegistry.trustedAdd(users[i].to, users[i].scheme, users[i].key, users[i].metadata);
            storageRent.credit(fid, users[i].units);
        }
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
