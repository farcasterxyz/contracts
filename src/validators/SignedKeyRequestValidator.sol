// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

import {EIP712} from "../abstract/EIP712.sol";
import {IMetadataValidator} from "../interfaces/IMetadataValidator.sol";
import {IdRegistryLike} from "../interfaces/IdRegistryLike.sol";

/**
 * @title Farcaster SignedKeyRequestValidator
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract SignedKeyRequestValidator is IMetadataValidator, Ownable2Step, EIP712 {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Signed key request specific metadata.
     *
     *  @param requestFid    The fid of the entity requesting to add
     *                       a signer key.
     *  @param requestSigner Signer address. Must be the owner of
     *                       requestFid.
     *  @param signature     EIP-712 SignedKeyRequest signature.
     *  @param deadline      block.timestamp after which signature expires.
     */
    struct SignedKeyRequestMetadata {
        uint256 requestFid;
        address requestSigner;
        bytes signature;
        uint256 deadline;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the admin sets a new IdRegistry contract address.
     *
     * @param oldIdRegistry The previous IdRegistry address.
     * @param newIdRegistry The new IdRegistry address.
     */
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Contract version specified using Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.08.23";

    bytes32 public constant METADATA_TYPEHASH =
        keccak256("SignedKeyRequest(uint256 requestFid,bytes key,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The IdRegistry contract.
     */
    IdRegistryLike public idRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the IdRegistry and owner.
     *
     * @param _idRegistry   IdRegistry contract address.
     * @param _initialOwner Initial contract owner address.
     */
    constructor(address _idRegistry, address _initialOwner) EIP712("Farcaster SignedKeyRequestValidator", "1") {
        idRegistry = IdRegistryLike(_idRegistry);
        _transferOwnership(_initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate the SignedKeyRequest metadata associated with a signer key.
     *         (Key type 1, Metadata type 1)
     *
     * @param key                   The EdDSA public key of the signer.
     * @param signedKeyRequestBytes An abi-encoded SignedKeyRequest struct, provided as the
     *                              metadata argument to KeyRegistry.add.
     *
     * @return true if signature is valid and signer owns requestFid, false otherwise.
     */
    function validate(
        uint256, /* userFid */
        bytes memory key,
        bytes calldata signedKeyRequestBytes
    ) external view returns (bool) {
        SignedKeyRequestMetadata memory metadata = abi.decode(signedKeyRequestBytes, (SignedKeyRequestMetadata));

        if (idRegistry.idOf(metadata.requestSigner) != metadata.requestFid) {
            return false;
        }
        if (block.timestamp > metadata.deadline) return false;
        if (key.length != 32) return false;

        return idRegistry.verifyFidSignature(
            metadata.requestSigner,
            metadata.requestFid,
            _hashTypedDataV4(
                keccak256(abi.encode(METADATA_TYPEHASH, metadata.requestFid, keccak256(key), metadata.deadline))
            ),
            metadata.signature
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice ABI-encode a SignedKeyRequestMetadata struct.
     *
     * @param metadata The SignedKeyRequestMetadata struct to encode.
     *
     * @return bytes memory Bytes of ABI-encoded struct.
     */
    function encodeMetadata(
        SignedKeyRequestMetadata calldata metadata
    ) external pure returns (bytes memory) {
        return abi.encode(metadata);
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the IdRegistry contract address. Only callable by owner.
     *
     * @param _idRegistry The new IdRegistry address.
     */
    function setIdRegistry(
        address _idRegistry
    ) external onlyOwner {
        emit SetIdRegistry(address(idRegistry), _idRegistry);
        idRegistry = IdRegistryLike(_idRegistry);
    }
}
