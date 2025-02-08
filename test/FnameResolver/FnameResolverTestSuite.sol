// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {FnameResolver} from "../../src/FnameResolver.sol";

/* solhint-disable state-visibility */

abstract contract FnameResolverTestSuite is TestSuiteSetup {
    FnameResolver internal resolver;

    string internal constant FNAME_SERVER_URL = "https://fnames.fcast.id/ccip/{sender}/{data}.json";

    /**
     * @dev DNS-encoding of "alice.fcast.id". The DNS-encoded name consists of:
     *      - 1 byte for the length of the first label (5)
     *      - 5 bytes for the label ("alice")
     *      - 1 byte for the length of the second label (5)
     *      - 5 bytes for the label ("fcast")
     *      - 1 byte for the length of the third label (2)
     *      - 2 bytes for the label ("id")
     *      - A null byte terminating the encoded name.
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
        resolver = new FnameResolver(FNAME_SERVER_URL, signer, owner);
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
