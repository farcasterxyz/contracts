// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IMetadataValidator} from "../interfaces/IMetadataValidator.sol";
import {IdRegistryLike} from "../interfaces/IdRegistryLike.sol";
import {IdRegistry} from "../IdRegistry.sol";

contract AppIdValidator is IMetadataValidator, Ownable2Step, EIP712 {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice App ID specific metadata.
     *
     *  @param appFid     The fid of the applcation associated with
     *                       the signer key.
     *  @param appSigner  Signer address. Must be the owner of
     *                    the appFid fid.
     *  @param signature  EIP-712 AppId signature.
     */
    struct AppId {
        uint256 appFid;
        address appSigner;
        bytes signature;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the admin sets a new IdRegistry contract address.
     *
     * @param oldIdRegistry The previous IdRegistry address.
     * @param newIdRegistry The ne IdRegistry address.
     */
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant _METADATA_TYPEHASH = keccak256("AppId(uint256 userFid,uint256 appFid,bytes signerPubKey)");

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
     * @notice Validate the AppId metadata associated with a signer key.
     *         (Scheme 1, Metadata typeId 1)
     *
     * @param userFid       The fid of the end user adding this signer key.
     * @param signerPubKey  The public key of the signer.
     * @param appIdBytes    An abi-encoded AppId struct, provided as the
     *                      metadata argument to KeyRegistry.add.
     *
     * @return true if signature is valid and signer owns appFid, false otherwise.
     */
    function validate(
        uint256 userFid,
        bytes memory signerPubKey,
        bytes calldata appIdBytes
    ) external view returns (bool) {
        AppId memory appId = abi.decode(appIdBytes[1:], (AppId));

        if (idRegistry.idOf(appId.appSigner) != appId.appFid) return false;

        /**
         *  Safety: Since keys may only be registered once, they are not
         *  vulnerable to replay, so we omit nonce and deadline in the
         *  validation signature.
         */
        return idRegistry.verifyFidSignature(
            appId.appSigner,
            appId.appFid,
            _hashTypedDataV4(keccak256(abi.encode(_METADATA_TYPEHASH, userFid, appId.appFid, keccak256(signerPubKey)))),
            appId.signature
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
