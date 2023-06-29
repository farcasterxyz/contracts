// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

bytes32 constant USERNAME_PROOF_TYPEHASH = keccak256("UsernameProof(string name,uint256 timestamp,address owner)");

struct UsernameProof {
    string name;
    uint256 timestamp;
    address owner;
}

contract FnameResolver is EIP712, Ownable2Step {
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
     * @dev Contract version. Follows Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.07.12";

    /**
     * @dev EIP-712 typehash of the UsernameProof struct.
     */
    bytes32 internal constant _USERNAME_PROOF_TYPEHASH =
        keccak256("UsernameProof(string name,uint256 timestamp,address owner)");

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
     * @notice Set the lookup gateway URL, and initial signer.
     *
     * @param _url                     Lookup gateway URL. This value is set permanently.
     * @param _signer                  Initial authorized signer address.
     */
    constructor(string memory _url, address _signer) EIP712("Farcaster name verification", "1") {
        url = _url;
        signers[_signer] = true;
        emit AddSigner(_signer);
    }

    /*//////////////////////////////////////////////////////////////
                             RESOLVER VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Resolve the provided ENS name. This function will always revert to indicate an offchain lookup.
     */
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory) {
        bytes memory callData = abi.encodeCall(this.resolve, (name, data));
        string[] memory urls = new string[](1);
        urls[0] = url;
        revert OffchainLookup(address(this), urls, callData, this.resolveWithProof.selector, callData);
    }

    /**
     * @notice Offchain lookup callback. The caller must provide the signed response returned by the lookup gateway.
     */
    function resolveWithProof(
        bytes calldata response,
        bytes calldata /* extraData */
    ) external view returns (bytes memory) {
        (bytes memory result, UsernameProof memory proof, bytes memory signature) =
            abi.decode(response, (bytes, UsernameProof, bytes));
        bytes32 eip712hash =
            _hashTypedDataV4(keccak256(abi.encode(USERNAME_PROOF_TYPEHASH, proof.name, proof.timestamp, proof.owner)));
        address signer = ECDSA.recover(eip712hash, signature);
        if (!signers[signer]) revert InvalidSigner();
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
    function addSigner(address signer) external onlyOwner {
        signers[signer] = true;
        emit AddSigner(signer);
    }

    /**
     * @notice Remove a signer address from the authorized mapping. Only callable by owner.
     *
     * @param signer The signer address.
     */
    function removeSigner(address signer) external onlyOwner {
        signers[signer] = false;
        emit RemoveSigner(signer);
    }
}
