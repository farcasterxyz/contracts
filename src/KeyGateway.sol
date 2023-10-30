// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Nonces} from "openzeppelin-latest/contracts/utils/Nonces.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";

import {IKeyGateway} from "./interfaces/IKeyGateway.sol";
import {IStorageRegistry} from "./interfaces/IStorageRegistry.sol";
import {IKeyRegistry} from "./interfaces/IKeyRegistry.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Guardians} from "./lib/Guardians.sol";
import {Signatures} from "./lib/Signatures.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";

/**
 * @title Farcaster KeyGateway
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.0.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@farcaster.xyz
 */
contract KeyGateway is IKeyGateway, Guardians, Signatures, EIP712, Nonces {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyGateway
     */
    string public constant VERSION = "2023.10.04";

    /**
     * @inheritdoc IKeyGateway
     */
    bytes32 public constant ADD_TYPEHASH = keccak256(
        "Add(address owner,uint32 keyType,bytes key,uint8 metadataType,bytes metadata,uint256 nonce,uint256 deadline)"
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyGateway
     */
    IKeyRegistry public immutable keyRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _keyRegistry,
        address _initialOwner
    ) Guardians(_initialOwner) EIP712("Farcaster KeyGateway", "1") {
        keyRegistry = IKeyRegistry(_keyRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                              REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IKeyGateway
     */
    function add(
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata
    ) external whenNotPaused returns (uint256 overpayment) {
        keyRegistry.add(msg.sender, keyType, key, metadataType, metadata);
    }

    /**
     * @inheritdoc IKeyGateway
     */
    function addFor(
        address fidOwner,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint256 deadline,
        bytes calldata sig
    ) external whenNotPaused returns (uint256 overpayment) {
        _verifyAddSig(fidOwner, keyType, key, metadataType, metadata, deadline, sig);
        keyRegistry.add(fidOwner, keyType, key, metadataType, metadata);
    }

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifyAddSig(
        address fidOwner,
        uint32 keyType,
        bytes memory key,
        uint8 metadataType,
        bytes memory metadata,
        uint256 deadline,
        bytes memory sig
    ) internal {
        _verifySig(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        ADD_TYPEHASH,
                        fidOwner,
                        keyType,
                        keccak256(key),
                        metadataType,
                        keccak256(metadata),
                        _useNonce(fidOwner),
                        deadline
                    )
                )
            ),
            fidOwner,
            deadline,
            sig
        );
    }
}
