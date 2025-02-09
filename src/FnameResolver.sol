// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC165} from "openzeppelin/contracts/utils/introspection/ERC165.sol";

import {EIP712} from "./abstract/EIP712.sol";

interface IExtendedResolver {
    function resolve(bytes memory name, bytes memory data) external view returns (bytes memory);
}

interface IResolverService {
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory result, uint256 timestamp, address owner, bytes memory signature);
}

/**
 * @title Farcaster FnameResolver
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/v3.1.0/docs/docs.md for an overview.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract FnameResolver is IExtendedResolver, EIP712, ERC165, Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Revert to indicate an offchain CCIP lookup. See: https://eips.ethereum.org/EIPS/eip-3668
     *
     * @param sender           Address of this contract.
     * @param urls             List of lookup gateway URLs.
     * @param callData         Data to call the gateway with.
     * @param callbackFunction 4 byte function selector of the callback function on this contract.
     * @param extraData        Additional data required by the callback function.
     */
    error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);

    /// @dev Revert queries for unimplemented resolver functions.
    error ResolverFunctionNotSupported();

    /// @dev Revert if the text record key is not allowed.
    error TextRecordNotSupported();

    /// @dev Revert if the recovered signer address is not an authorized signer.
    error InvalidSigner();

    /// @dev Revert if the extra data hash does not match the original request.
    error MismatchedRequest();

    /// @dev Revert if the signature is expired.
    error ExpiredSignature();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the contract owner authorizes a new signer.
     *
     * @param signer Address of the authorized signer.
     */
    event AddSigner(address indexed signer);

    /**
     * @dev Emit an event when the contract owner removes an authorized signer.
     *
     * @param signer Address of the removed signer.
     */
    event RemoveSigner(address indexed signer);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Contract version specified using Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.08.23";

    /**
     * @dev EIP-712 typehash of the DataProof struct.
     */
    bytes32 public constant DATA_PROOF_TYPEHASH =
        keccak256("DataProof(bytes32 request,bytes32 result,uint256 validUntil)");

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev URL of the CCIP lookup gateway.
     */
    string public url;

    /**
     * @dev Mapping of signer address to authorized boolean.
     */
    mapping(address signer => bool isAuthorized) public signers;

    /**
     * @dev Mapping of resolver function selector to allowed boolean.
     */
    mapping(bytes4 selector => bool isAllowed) public allowedSelectors;

    /**
     * @dev Mapping of text record key to allowed boolean.
     */
    mapping(string textRecordKey => bool isAllowed) public allowedTextRecords;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the lookup gateway URL and initial signer.
     *
     * @param _url          Lookup gateway URL. This value is set permanently.
     * @param _signer       Initial authorized signer address.
     * @param _initialOwner Initial owner address.
     */
    constructor(
        string memory _url,
        address _signer,
        address _initialOwner
    ) EIP712("Farcaster name verification", "1") {
        _transferOwnership(_initialOwner);
        url = _url;
        signers[_signer] = true;
        emit AddSigner(_signer);

        // Only support `addr(node)`, `addr(node, cointype)` and `text(node, key)`
        allowedSelectors[0x3b3b57de] = true;
        allowedSelectors[0xf1cb7e06] = true;
        allowedSelectors[0x59d1d43c] = true;

        // Only support `avatar`, `description` and `url`
        allowedTextRecords["avatar"] = true;
        allowedTextRecords["description"] = true;
        allowedTextRecords["url"] = true;
    }

    /*//////////////////////////////////////////////////////////////
                             RESOLVER VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Resolve the provided ENS name. This function will always revert to indicate an
     *         offchain lookup.
     *
     * @param name DNS-encoded name to resolve.
     * @param data Encoded calldata of an ENS resolver function. This resolver supports only
     *             address resolution (Signature 0x3b3b57de). Calling the CCIP gateway with any
     *             other resolver function will revert.
     */
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory) {
        if (!allowedSelectors[bytes4(data[:4])]) revert ResolverFunctionNotSupported();

        // Save requests to the gateway by only forwarding certain text record lookups
        if (bytes4(data[:4]) == 0x59d1d43c) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            if (!allowedTextRecords[key]) revert TextRecordNotSupported();
        }

        bytes memory callData = abi.encodeCall(IResolverService.resolve, (name, data));
        string[] memory urls = new string[](1);
        urls[0] = url;

        revert OffchainLookup(address(this), urls, callData, this.resolveWithProof.selector, callData);
    }

    /**
     * @notice Offchain lookup callback. The caller must provide the signed response returned by
     *         the lookup gateway.
     *
     * @param response Response from the CCIP gateway which has the following ABI-encoded fields:
     *                 - string: Fname of the username proof.
     *                 - uint256: Timestamp of the username proof.
     *                 - address: Owner address that signed the username proof.
     *                 - bytes: EIP-712 signature provided by the CCIP gateway server.
     * @param extraData Calldata from the original resolve() call. Used to verify that the gateway is answering the
     *                  right query.
     *
     * @return ABI-encoded data (can be address or text record).
     */
    function resolveWithProof(bytes calldata response, bytes calldata extraData) external view returns (bytes memory) {
        (bytes32 extraDataHash, bytes memory result, uint256 validUntil, bytes memory signature) =
            abi.decode(response, (bytes32, bytes, uint256, bytes));

        bytes32 proofHash = keccak256(abi.encode(DATA_PROOF_TYPEHASH, extraDataHash, keccak256(result), validUntil));
        bytes32 eip712hash = _hashTypedDataV4(proofHash);
        address signer = ECDSA.recover(eip712hash, signature);

        if (!signers[signer]) revert InvalidSigner();
        if (block.timestamp > validUntil) revert ExpiredSignature();
        if (keccak256(extraData) != extraDataHash) revert MismatchedRequest();

        return result;
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a signer address to the authorized mapping. Only callable by owner.
     *
     * @param signer The signer address.
     */
    function addSigner(
        address signer
    ) external onlyOwner {
        signers[signer] = true;
        emit AddSigner(signer);
    }

    /**
     * @notice Remove a signer address from the authorized mapping. Only callable by owner.
     *
     * @param signer The signer address.
     */
    function removeSigner(
        address signer
    ) external onlyOwner {
        signers[signer] = false;
        emit RemoveSigner(signer);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERFACE DETECTION
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return interfaceId == type(IExtendedResolver).interfaceId || super.supportsInterface(interfaceId);
    }
}
