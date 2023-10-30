// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IKeyRegistry} from "./IKeyRegistry.sol";

interface IKeyGateway {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice EIP-712 typehash for Add signatures.
     */
    function ADD_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The KeyRegistry contract.
     */
    function keyRegistry() external view returns (IKeyRegistry);

    /*//////////////////////////////////////////////////////////////
                              REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a key associated with the caller's fid, setting the key state to ADDED.
     *         The caller must provide at least fee() wei of payment. Any excess payment
     *         will be refunded to the caller.
     *
     * @param keyType      The key's numeric keyType.
     * @param key          Bytes of the key to add.
     * @param metadataType Metadata type ID.
     * @param metadata     Metadata about the key, which is not stored and only emitted in an event.
     */
    function add(uint32 keyType, bytes calldata key, uint8 metadataType, bytes calldata metadata) external;

    /**
     * @notice Add a key on behalf of another fid owner, setting the key state to ADDED.
     *         caller must supply a valid EIP-712 Add signature from the fid owner.
     *         Caller must provide at least fee() wei of payment. Any excess payment
     *         will be refunded to the caller.
     *
     * @param fidOwner     The fid owner address.
     * @param keyType      The key's numeric keyType.
     * @param key          Bytes of the key to add.
     * @param metadataType Metadata type ID.
     * @param metadata     Metadata about the key, which is not stored and only emitted in an event.
     * @param deadline     Deadline after which the signature expires.
     * @param sig          EIP-712 Add signature generated by fid owner.
     */
    function addFor(
        address fidOwner,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint256 deadline,
        bytes calldata sig
    ) external;
}
