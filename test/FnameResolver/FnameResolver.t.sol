// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../TestConstants.sol";
import {FnameResolverTestSuite} from "./FnameResolverTestSuite.sol";
import {FnameResolver, UsernameProof, USERNAME_PROOF_TYPEHASH} from "../../src/FnameResolver.sol";

/* solhint-disable state-visibility */

contract FnameResolverTest is FnameResolverTestSuite {
    event AddSigner(address indexed signer);
    event RemoveSigner(address indexed signer);

    function testURL() public {
        assertEq(resolver.url(), FNAME_SERVER_URL);
    }

    function testSignerIsAuthorized() public {
        assertEq(resolver.signers(signer), true);
    }

    function testFuzzResolveRevertsWithOffchainLookup(bytes calldata name, bytes calldata data) public {
        string[] memory urls = new string[](1);
        urls[0] = FNAME_SERVER_URL;

        bytes memory callData = abi.encodeCall(resolver.resolve, (name, data));

        bytes memory offchainLookup = abi.encodeWithSelector(
            FnameResolver.OffchainLookup.selector,
            address(resolver),
            urls,
            callData,
            resolver.resolveWithProof.selector,
            callData
        );
        vm.expectRevert(offchainLookup);
        resolver.resolve(name, data);
    }

    function testFuzzResolveWithProofValidSignature(
        string memory name,
        uint256 timestamp,
        address owner,
        bytes calldata result
    ) public {
        UsernameProof memory proof = UsernameProof({name: name, timestamp: timestamp, owner: owner});
        bytes memory signature = _signProof(name, timestamp, owner);

        bytes memory response = resolver.resolveWithProof(abi.encode(result, proof, signature), "");
        assertEq(response, result);
    }

    function testFuzzResolveWithProofInvalidOwner(
        string memory name,
        uint256 timestamp,
        address owner,
        bytes calldata result
    ) public {
        address wrongOwner = address(~uint160(owner));
        UsernameProof memory proof = UsernameProof({name: name, timestamp: timestamp, owner: wrongOwner});
        bytes memory signature = _signProof(name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(result, proof, signature), "");
    }

    function testFuzzResolveWithProofInvalidTimestamp(
        string memory name,
        uint256 timestamp,
        address owner,
        bytes calldata result
    ) public {
        uint256 wrongTimestamp = ~timestamp;
        UsernameProof memory proof = UsernameProof({name: name, timestamp: wrongTimestamp, owner: owner});
        bytes memory signature = _signProof(name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(result, proof, signature), "");
    }

    function testFuzzResolveWithProofInvalidName(
        string memory name,
        uint256 timestamp,
        address owner,
        bytes calldata result
    ) public {
        string memory wrongName = string.concat("~", name);
        UsernameProof memory proof = UsernameProof({name: wrongName, timestamp: timestamp, owner: owner});
        bytes memory signature = _signProof(name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(result, proof, signature), "");
    }

    function testFuzzResolveWithProofWrongSigner(
        string memory name,
        uint256 timestamp,
        address owner,
        bytes calldata result
    ) public {
        UsernameProof memory proof = UsernameProof({name: name, timestamp: timestamp, owner: owner});
        bytes memory signature = _signProof(malloryPk, name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(result, proof, signature), "");
    }

    function testFuzzResolveWithProofInvalidSignerLength(
        string memory name,
        uint256 timestamp,
        address owner,
        bytes calldata result,
        bytes memory signature,
        uint8 _length
    ) public {
        vm.assume(signature.length >= 65);
        uint256 length = bound(_length, 0, 64);
        assembly {
            mstore(signature, length)
        } /* truncate signature length */
        UsernameProof memory proof = UsernameProof({name: name, timestamp: timestamp, owner: owner});

        vm.expectRevert("ECDSA: invalid signature length");
        resolver.resolveWithProof(abi.encode(result, proof, signature), "");
    }

    function testFuzzOwnerCanAddSigner(address signer) public {
        vm.expectEmit(true, false, false, false);
        emit AddSigner(signer);

        vm.prank(owner);
        resolver.addSigner(signer);

        assertEq(resolver.signers(signer), true);
    }

    function testFuzzOnlyOwnerCanAddSigner(address caller, address signer) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        resolver.addSigner(signer);
    }

    function testFuzzOwnerCanRemoveSigner(address signer) public {
        vm.prank(owner);
        resolver.addSigner(signer);

        assertEq(resolver.signers(signer), true);

        vm.expectEmit(true, false, false, false);
        emit RemoveSigner(signer);

        vm.prank(owner);
        resolver.removeSigner(signer);

        assertEq(resolver.signers(signer), false);
    }

    function testFuzzOnlyOwnerCanRemoveSigner(address caller, address signer) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        resolver.removeSigner(signer);
    }

    function _signProof(
        string memory name,
        uint256 timestamp,
        address owner
    ) internal returns (bytes memory signature) {
        return _signProof(signerPk, name, timestamp, owner);
    }

    function _signProof(
        uint256 pk,
        string memory name,
        uint256 timestamp,
        address owner
    ) internal returns (bytes memory signature) {
        bytes32 eip712hash =
            resolver.hashTypedDataV4(keccak256(abi.encode(USERNAME_PROOF_TYPEHASH, name, timestamp, owner)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, eip712hash);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
