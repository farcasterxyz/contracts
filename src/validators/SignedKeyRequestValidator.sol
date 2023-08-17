// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IMetadataValidator} from "../interfaces/IMetadataValidator.sol";
import {IdRegistryLike} from "../interfaces/IdRegistryLike.sol";
import {IdRegistry} from "../IdRegistry.sol";

contract SignedKeyRequestValidator is IMetadataValidator, Ownable2Step, EIP712 {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Signed key request specific metadata.
     *
     *  @param requestingFid The fid of the entity requesting to add
     *                       a signer key.
     *  @param requestSigner Signer address. Must be the owner of
     *                       the requestingFid fid.
     *  @param signature     EIP-712 SignedKeyRequest signature.
     *  @param deadline      block.timestamp after which signature expires.
     */
    struct SignedKeyRequest {
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

    bytes32 internal constant _METADATA_TYPEHASH =
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
    constructor(address _idRegistry, address _initialOwner) EIP712("Farcaster MetadataValidator", "1") {
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
        SignedKeyRequest memory signedKeyRequest = abi.decode(signedKeyRequestBytes, (SignedKeyRequest));

        if (idRegistry.idOf(signedKeyRequest.requestSigner) != signedKeyRequest.requestFid) return false;
        if (block.timestamp > signedKeyRequest.deadline) return false;

        return idRegistry.verifyFidSignature(
            signedKeyRequest.requestSigner,
            signedKeyRequest.requestFid,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _METADATA_TYPEHASH, signedKeyRequest.requestFid, keccak256(key), signedKeyRequest.deadline
                    )
                )
            ),
            signedKeyRequest.signature
        );
    }

    /*//////////////////////////////////////////////////////////////
                            EIP-712 HELPERS
    //////////////////////////////////////////////////////////////*/

    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the IdRegistry contract address. Only callable by owner.
     *
     * @param _idRegistry The new IdRegistry address.
     */
    function setIdRegistry(address _idRegistry) external onlyOwner {
        emit SetIdRegistry(address(idRegistry), _idRegistry);
        idRegistry = IdRegistryLike(_idRegistry);
    }
}
