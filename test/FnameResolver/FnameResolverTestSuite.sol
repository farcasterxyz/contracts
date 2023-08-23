// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {FnameResolverHarness} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract FnameResolverTestSuite is TestSuiteSetup {
    FnameResolverHarness internal resolver;

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
    bytes internal constant DNS_ENCODED_NAME =
        (hex"05" hex"616c696365" hex"05" hex"6663617374" hex"02" hex"6964" hex"00");

    /**
     * @dev Encoded calldata for a call to addr(bytes32 node), where node is the ENS
     *      nameHash encoded value of "alice.fcast.id"
     */
    bytes internal constant ADDR_QUERY_CALLDATA = hex"c30dc5a16498c5b6d46f97ca0c74d092ebbee1290b1c88f6e435dd4fb306ca36";

    address internal signer;
    uint256 internal signerPk;

    address internal mallory;
    uint256 internal malloryPk;

    function setUp() public virtual override {
        (signer, signerPk) = makeAddrAndKey("signer");
        (mallory, malloryPk) = makeAddrAndKey("mallory");
        resolver = new FnameResolverHarness(FNAME_SERVER_URL, signer, owner);
    }
}
