// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC165} from "openzeppelin/contracts/utils/introspection/ERC165.sol";

import {EIP712} from "./abstract/EIP712.sol";

interface IAddressQuery {
    function addr(
        bytes32 node
    ) external view returns (address);
}

interface IExtendedResolver {
    function resolve(bytes memory name, bytes memory data) external view returns (bytes memory);
}

interface IResolverService {
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (string memory fname, uint256 timestamp, address owner, bytes memory signature);
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

    /// @dev Revert if the recovered signer address is not an authorized signer.
    error InvalidSigner();

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
     * @dev EIP-712 typehash of the UsernameProof struct.
     */
    bytes32 public constant USERNAME_PROOF_TYPEHASH =
        keccak256("UserNameProof(string name,uint256 timestamp,address owner)");

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
        if (bytes4(data[:4]) != IAddressQuery.addr.selector) {
            revert ResolverFunctionNotSupported();
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
     *
     * @return ABI-encoded address of the fname owner.
     */
    function resolveWithProof(
        bytes calldata response,
        bytes calldata /* extraData */
    ) external view returns (bytes memory) {
        (string memory fname, uint256 timestamp, address fnameOwner, bytes memory signature) =
            abi.decode(response, (string, uint256, address, bytes));

        bytes32 proofHash =
            keccak256(abi.encode(USERNAME_PROOF_TYPEHASH, keccak256(bytes(fname)), timestamp, fnameOwner));
        bytes32 eip712hash = _hashTypedDataV4(proofHash);
        address signer = ECDSA.recover(eip712hash, signature);

        if (!signers[signer]) revert InvalidSigner();

        return abi.encode(fnameOwner);
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
