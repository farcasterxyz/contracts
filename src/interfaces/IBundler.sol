// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IIdGateway} from "./IIdGateway.sol";
import {IKeyGateway} from "./IKeyGateway.sol";
import {IStorageRegistry} from "./IStorageRegistry.sol";

interface IBundler {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

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
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @dev Address of the IdGateway contract
     */
    function idGateway() external view returns (IIdGateway);

    /**
     * @dev Address of the KeyGateway contract
     */
    function keyGateway() external view returns (IKeyGateway);

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the total price of a registration.
     *
     * @param extraStorage Number of additional storage units to rent. All registrations include 1
     *                     storage unit, but additional storage can be rented at registration time.
     *
     * @return Total price in wei.
     *
     */
    function price(
        uint256 extraStorage
    ) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register an fid, add one or more signers, and rent storage in a single transaction.
     *
     * @param registerParams Struct containing register parameters: to, recovery, deadline, and signature.
     * @param signerParams   Array of structs containing signer parameters: keyType, key, metadataType,
     *                       metadata, deadline, and signature.
     * @param extraStorage   Number of additional storage units to rent. (fid registration includes 1 unit).
     *
     */
    function register(
        RegistrationParams calldata registerParams,
        SignerParams[] calldata signerParams,
        uint256 extraStorage
    ) external payable returns (uint256 fid);

    /**
     * @notice Add multiple keys in a single transaction.
     *
     * @param fidOwner       The fid owner address.
     * @param signerParams   Array of structs containing signer parameters: keyType, key, metadataType,
     *                       metadata, deadline, and signature.
     *
     */
    function addKeys(address fidOwner, SignerParams[] calldata signerParams) external;
}
