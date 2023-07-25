// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {FnameResolverHarness} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract FnameResolverTestSuite is TestSuiteSetup {
    FnameResolverHarness internal resolver;

    string internal constant FNAME_SERVER_URL = "https://fnames.farcaster.xyz/ccip/{sender}/{data}.json";

    /**
     * @dev DNS-encoding of "alice.farcaster.xyz". The DNS-encoded name consists of:
     *      - 1 byte for the length of the first label (5)
     *      - 5 bytes for the label ("alice")
     *      - 1 byte for the length of the second label (9)
     *      - 9 bytes for the label ("farcaster")
     *      - 1 byte for the length of the third label (3)
     *      - 3 bytes for the label ("xyz")
     *      - A null byte terminating the encoded name.
     */
    bytes internal constant DNS_ENCODED_NAME =
        (hex"05" hex"616c696365" hex"09" hex"666172636173746572" hex"03" hex"78797a" hex"00");

    /**
     * @dev Encoded calldata for a call to addr(bytes32 node), where node is the ENS
     *      nameHash encoded value of "alice.farcaster.xyz"
     */
    bytes internal constant ADDR_QUERY_CALLDATA =
        hex"3b3b57de00d4f449060ad2a07ff5ad355ae8da52281e95f6ad10fb923ae7cad9f2c43c2a";

    address internal signer;
    uint256 internal signerPk;

    address internal mallory;
    uint256 internal malloryPk;

    function setUp() public override {
        (signer, signerPk) = makeAddrAndKey("signer");
        (mallory, malloryPk) = makeAddrAndKey("mallory");
        resolver = new FnameResolverHarness(FNAME_SERVER_URL, signer, owner);
    }
}
