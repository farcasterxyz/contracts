// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IBundler {
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
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                          REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register an fid, multiple signers, and rent storage to an address in a single transaction.
     *
     * @param registration Struct containing registration parameters: to, recovery, deadline, and signature.
     * @param signers      Array of structs containing signer parameters: keyType, key, metadataType, metadata, deadline, and signature.
     * @param storageUnits Number of storage units to rent
     *
     */
    function register(
        RegistrationParams calldata registration,
        SignerParams[] calldata signers,
        uint256 storageUnits
    ) external payable;

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register an fid, add a signer, and credit storage to an address in a single transaction. Can only
     *         be called by the trustedCaller during the Seedable phase.
     *
     * @param user UserData struct including to/recovery address, key params, and number of storage units.
     */
    function trustedRegister(UserData calldata user) external;

    /**
     * @notice Register fids, keys, and credit storage for multiple users in a single transaction. Can
     *         only be called by the trustedCaller during the Seedable phase. Will be used when
     *         migrating across Ethereum networks to bootstrap a new contract with existing data.
     *
     * @param users  Array of UserData structs to register
     */
    function trustedBatchRegister(UserData[] calldata users) external;
}
