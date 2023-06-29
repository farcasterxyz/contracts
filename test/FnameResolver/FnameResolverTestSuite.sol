// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {EIP712} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {FnameResolverHarness} from "../Utils.sol";

/* solhint-disable state-visibility */

abstract contract FnameResolverTestSuite is Test {
    FnameResolverHarness internal resolver;

    string internal constant FNAME_SERVER_URL = "https://fnames.farcaster.xyz/";

    address internal signer;
    uint256 internal signerPk;

    address internal mallory;
    uint256 internal malloryPk;

    address internal owner = address(this);

    function setUp() public {
        (signer, signerPk) = makeAddrAndKey("signer");
        (mallory, malloryPk) = makeAddrAndKey("mallory");
        resolver = new FnameResolverHarness(FNAME_SERVER_URL, signer);
    }
}
