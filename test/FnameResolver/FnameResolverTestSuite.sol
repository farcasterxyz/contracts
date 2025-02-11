// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {FnameResolver, IExtendedResolver} from "../../src/FnameResolver.sol";

/* solhint-disable state-visibility */

abstract contract FnameResolverTestSuite is TestSuiteSetup {
    FnameResolver internal resolver;

    string internal constant FNAME_SERVER_URL = "https://fnames.fcast.id/ccip/{sender}/{data}.json";

    /**
     * @dev DNS-encoding of "farcaster.eth"
     */
    bytes internal constant PARENT_DNS_ENCODED_NAME = hex"096661726361737465720365746800";

    /**
     * @dev Address of the passthrough resolver, which must also support ENSIP-10.
     *      This will likely be the ENS Public Resolver.
     */
    IExtendedResolver internal PASSTHROUGH_RESOLVER = new MockResolver();

    /**
     * @dev DNS-encoding of "alice.farcaster.eth"
     */
    bytes internal constant DNS_ENCODED_NAME = hex"05616c696365096661726361737465720365746800";

    /**
     * @dev Namehash of "alice.farcaster.eth"
     */
    bytes internal constant ENS_NODE = hex"e224cf2d7e9641e5b9cde025d9e3db25df5d8789bb7a5c9f4bb28b3e18c2717e";

    /**
     * @dev Encoded calldata for a call to addr(bytes32 node), where node is the ENS
     *      nameHash encoded value of "alice.farcaster.eth"
     */
    bytes internal constant ADDR_QUERY_CALLDATA = hex"e224cf2d7e9641e5b9cde025d9e3db25df5d8789bb7a5c9f4bb28b3e18c2717e";

    address internal signer;
    uint256 internal signerPk;

    address internal mallory;
    uint256 internal malloryPk;

    function setUp() public virtual override {
        (signer, signerPk) = makeAddrAndKey("signer");
        (mallory, malloryPk) = makeAddrAndKey("mallory");
        resolver = new FnameResolver(PARENT_DNS_ENCODED_NAME, PASSTHROUGH_RESOLVER, FNAME_SERVER_URL, signer, owner);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _signProof(
        bytes32 requestHash,
        bytes memory result,
        uint256 validUntil
    ) internal returns (bytes memory signature) {
        return _signProof(signerPk, requestHash, result, validUntil);
    }

    function _signProof(
        uint256 pk,
        bytes32 requestHash,
        bytes memory result,
        uint256 validUntil
    ) internal returns (bytes memory signature) {
        bytes32 eip712hash = resolver.hashTypedDataV4(
            keccak256(abi.encode(resolver.DATA_PROOF_TYPEHASH(), requestHash, keccak256(result), validUntil))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, eip712hash);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}

contract MockResolver is IExtendedResolver {
    function resolve(bytes calldata, bytes calldata data) external view returns (bytes memory) {
        // text(node, key)
        if (bytes4(data[:4]) == 0x59d1d43c) {
            return abi.encode("farcaster");
        }

        // addr(node)
        if (bytes4(data[:4]) == 0x3b3b57de) {
            return abi.encode(address(this));
        }

        // addr(node, cointype)
        if (bytes4(data[:4]) == 0xf1cb7e06) {
            return abi.encode(abi.encodePacked(address(this)));
        }

        // covers empty result for all standard resolver methods
        return new bytes(64);
    }
}
