// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IERC165} from "openzeppelin/contracts/utils/introspection/IERC165.sol";

import {FnameResolverTestSuite} from "./FnameResolverTestSuite.sol";
import {FnameResolver, IResolverService, IExtendedResolver} from "../../src/FnameResolver.sol";

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

    function testName() public {
        assertEq(resolver.dnsEncodedName(), PARENT_DNS_ENCODED_NAME);
    }

    function testPassthroughResolver() public {
        assertEq(address(resolver.passthroughResolver()), address(PASSTHROUGH_RESOLVER));
    }

    /*//////////////////////////////////////////////////////////////
                                 RESOLVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzResolveRevertsWithOffchainLookup(bytes calldata name, bytes memory data) public {
        data = bytes.concat(bytes4(0x3b3b57de), data);
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

    function testRevertsWithOffchainLookupForTextRecord() public {
        string[] memory keys = new string[](3);
        keys[0] = "avatar";
        keys[1] = "description";
        keys[2] = "url";

        string[] memory urls = new string[](1);
        urls[0] = FNAME_SERVER_URL;

        for (uint256 i = 0; i < keys.length; i++) {
            bytes memory textCallData = abi.encodeWithSelector(0x59d1d43c, ENS_NODE, keys[i]);
            bytes memory callData = abi.encodeCall(resolver.resolve, (DNS_ENCODED_NAME, textCallData));

            bytes memory offchainLookup = abi.encodeWithSelector(
                FnameResolver.OffchainLookup.selector,
                address(resolver),
                urls,
                callData,
                resolver.resolveWithProof.selector,
                callData
            );

            vm.expectRevert(offchainLookup);
            resolver.resolve(DNS_ENCODED_NAME, textCallData);
        }
    }

    function testFuzzResolveRevertsUnsupportedFunction(bytes calldata name, bytes memory data) public {
        data = bytes.concat(hex"00000001", data);
        string[] memory urls = new string[](1);
        urls[0] = FNAME_SERVER_URL;

        vm.expectRevert(FnameResolver.ResolverFunctionNotSupported.selector);
        resolver.resolve(name, data);
    }

    function testFuzzResolveEmptyForUnsupportedTextRecord(
        string memory key
    ) public {
        // Calldata for the text(node, key) function (signature 0x59d1d43c)
        bytes memory textCallData = abi.encodeWithSelector(0x59d1d43c, ENS_NODE, key);

        string[] memory urls = new string[](1);
        urls[0] = FNAME_SERVER_URL;

        bytes memory result = resolver.resolve(DNS_ENCODED_NAME, textCallData);
        assertEq(result, abi.encode(""));
    }

    function testFuzzResolvePassthrough(
        string memory key
    ) public {
        // namehash("farcaster.eth")
        bytes32 node = 0x69d89a3b352fc56b7b2f65be229e08de44303dab8b7fd10e9f104766f17bdf29;
        bytes memory textCallData = abi.encodeWithSelector(0x59d1d43c, node, key);

        bytes memory result = resolver.passthroughResolver().resolve(PARENT_DNS_ENCODED_NAME, textCallData);
        assertEq(result, abi.encode("farcaster"));
    }

    /*//////////////////////////////////////////////////////////////
                           RESOLVE WITH PROOF
    //////////////////////////////////////////////////////////////*/

    function testFuzzResolveWithProofValidSignature(bytes memory result, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes32 extraDataHash = keccak256(extraData);
        bytes memory signature = _signProof(extraDataHash, result, validUntil);
        bytes memory response =
            resolver.resolveWithProof(abi.encode(extraDataHash, result, validUntil, signature), extraData);
        assertEq(response, result);
    }

    function testFuzzResolveWithProofMismatchingRequest(bytes memory result, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes32 extraDataHash = keccak256(extraData);
        bytes memory signature = _signProof(extraDataHash, result, validUntil);
        vm.expectRevert(FnameResolver.MismatchedRequest.selector);
        resolver.resolveWithProof(abi.encode(extraDataHash, result, validUntil, signature), "");
    }

    function testFuzzResolveWithProofExpiredSignature(bytes memory result, uint256 validUntil) public {
        vm.assume(validUntil < block.timestamp);
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes32 extraDataHash = keccak256(extraData);
        bytes memory signature = _signProof(extraDataHash, result, validUntil);
        vm.expectRevert(FnameResolver.ExpiredSignature.selector);
        resolver.resolveWithProof(abi.encode(extraDataHash, result, validUntil, signature), extraData);
    }

    function testFuzzResolveWithProofWrongSigner(bytes memory result, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes32 extraDataHash = keccak256(extraData);
        bytes memory signature = _signProof(malloryPk, extraDataHash, result, validUntil);

        vm.expectRevert(FnameResolver.InvalidSigner.selector);
        resolver.resolveWithProof(abi.encode(extraDataHash, result, validUntil, signature), extraData);
    }

    function testFuzzResolveWithProofInvalidSignerLength(
        bytes32 extraDataHash,
        bytes memory result,
        uint256 validUntil,
        bytes memory signature,
        uint8 _length
    ) public {
        vm.assume(signature.length >= 65);
        uint256 length = bound(_length, 0, 64);
        assembly {
            mstore(signature, length)
        } /* truncate signature length */

        vm.expectRevert("ECDSA: invalid signature length");
        resolver.resolveWithProof(abi.encode(extraDataHash, result, validUntil, signature), "");
    }

    function testProofTypehash() public {
        assertEq(
            resolver.DATA_PROOF_TYPEHASH(), keccak256("DataProof(bytes32 request,bytes32 result,uint256 validUntil)")
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
