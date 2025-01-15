// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IERC165} from "openzeppelin/contracts/utils/introspection/IERC165.sol";

import {FnameResolverTestSuite} from "./FnameResolverTestSuite.sol";
import {FnameResolver, IResolverService, IExtendedResolver, IAddressQuery} from "../../src/FnameResolver.sol";

/* solhint-disable state-visibility */

contract FnameResolverTest is FnameResolverTestSuite {
    event AddSigner(address indexed signer);
    event RemoveSigner(address indexed signer);

    function testURL() public {
        assertEq(resolver.url(), FNAME_SERVER_URL);
    }

    function testInitialOwner() public {
        assertEq(resolver.owner(), owner);
    }

    function testSignerIsAuthorized() public {
        assertEq(resolver.signers(signer), true);
    }

    function testVersion() public {
        assertEq(resolver.VERSION(), "2023.08.23");
    }

    /*//////////////////////////////////////////////////////////////
                                 RESOLVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzResolveRevertsWithOffchainLookup(bytes calldata name, bytes memory data) public {
        data = bytes.concat(IAddressQuery.addr.selector, data);
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

    function testFuzzResolveRevertsNonAddrFunction(bytes calldata name, bytes memory data) public {
        data = bytes.concat(hex"00000001", data);
        string[] memory urls = new string[](1);
        urls[0] = FNAME_SERVER_URL;

        vm.expectRevert(FnameResolver.ResolverFunctionNotSupported.selector);
        resolver.resolve(name, data);
    }

    /*//////////////////////////////////////////////////////////////
                           RESOLVE WITH PROOF
    //////////////////////////////////////////////////////////////*/

    function testFuzzResolveWithProofValidSignature(string memory name, uint256 timestamp, address owner) public {
        bytes memory signature = _signProof(name, timestamp, owner);
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes memory response = resolver.resolveWithProof(abi.encode(name, timestamp, owner, signature), extraData);
        assertEq(response, abi.encode(owner));
    }

    function testFuzzResolveWithProofInvalidOwner(string memory name, uint256 timestamp, address owner) public {
        address wrongOwner = address(~uint160(owner));
        bytes memory signature = _signProof(name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(name, timestamp, wrongOwner, signature), "");
    }

    function testFuzzResolveWithProofInvalidTimestamp(string memory name, uint256 timestamp, address owner) public {
        uint256 wrongTimestamp = ~timestamp;
        bytes memory signature = _signProof(name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(name, wrongTimestamp, owner, signature), "");
    }

    function testFuzzResolveWithProofInvalidName(string memory name, uint256 timestamp, address owner) public {
        string memory wrongName = string.concat("~", name);
        bytes memory signature = _signProof(name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(wrongName, timestamp, owner, signature), "");
    }

    function testFuzzResolveWithProofWrongSigner(string memory name, uint256 timestamp, address owner) public {
        bytes memory signature = _signProof(malloryPk, name, timestamp, owner);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(name, timestamp, owner, signature), "");
    }

    function testFuzzResolveWithProofInvalidSignerLength(
        string memory name,
        uint256 timestamp,
        address owner,
        bytes memory signature,
        uint8 _length
    ) public {
        vm.assume(signature.length >= 65);
        uint256 length = bound(_length, 0, 64);
        assembly {
            mstore(signature, length)
        } /* truncate signature length */

        vm.expectRevert("ECDSA: invalid signature length");
        resolver.resolveWithProof(abi.encode(name, timestamp, owner, signature), "");
    }

    function testProofTypehash() public {
        assertEq(
            resolver.USERNAME_PROOF_TYPEHASH(), keccak256("UserNameProof(string name,uint256 timestamp,address owner)")
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 SIGNERS
    //////////////////////////////////////////////////////////////*/

    function testFuzzOwnerCanAddSigner(
        address signer
    ) public {
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

    function testFuzzOwnerCanRemoveSigner(
        address signer
    ) public {
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

    /*//////////////////////////////////////////////////////////////
                           INTERFACE DETECTION
    //////////////////////////////////////////////////////////////*/

    function testInterfaceDetectionIExtendedResolver() public {
        assertEq(resolver.supportsInterface(type(IExtendedResolver).interfaceId), true);
    }

    function testInterfaceDetectionERC165() public {
        assertEq(resolver.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testFuzzInterfaceDetectionUnsupportedInterface(
        bytes4 interfaceId
    ) public {
        vm.assume(interfaceId != type(IExtendedResolver).interfaceId && interfaceId != type(IERC165).interfaceId);
        assertEq(resolver.supportsInterface(interfaceId), false);
    }
}
