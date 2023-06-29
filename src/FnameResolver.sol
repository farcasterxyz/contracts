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
    error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);
    error InvalidSignature();

    event AddSigner(address indexed signer);
    event RemoveSigner(address indexed signer);

    string public url;

    mapping(address signer => bool isAuthorized) public signers;

    constructor(string memory _url, address _signer) EIP712("Farcaster name verification", "1") {
        url = _url;
        signers[_signer] = true;
        emit AddSigner(_signer);
    }

    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory) {
        bytes memory callData = abi.encodeCall(this.resolve, (name, data));
        string[] memory urls = new string[](1);
        urls[0] = url;
        revert OffchainLookup(address(this), urls, callData, this.resolveWithProof.selector, callData);
    }

    function resolveWithProof(
        bytes calldata response,
        bytes calldata /* extraData */
    ) external view returns (bytes memory) {
        (bytes memory result, UsernameProof memory proof, bytes memory signature) =
            abi.decode(response, (bytes, UsernameProof, bytes));
        bytes32 eip712hash =
            _hashTypedDataV4(keccak256(abi.encode(USERNAME_PROOF_TYPEHASH, proof.name, proof.timestamp, proof.owner)));
        address signer = ECDSA.recover(eip712hash, signature);
        if (!signers[signer]) revert InvalidSignature();
        return result;
    }

    function addSigner(address signer) external onlyOwner {
        signers[signer] = true;
        emit AddSigner(signer);
    }

    function removeSigner(address signer) external onlyOwner {
        signers[signer] = false;
        emit RemoveSigner(signer);
    }
}
