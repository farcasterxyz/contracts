// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {DeployL1, FnameResolver} from "../../script/DeployL1.s.sol";
import {IResolverService} from "../../src/FnameResolver.sol";
import {FnameResolverTestSuite} from "../../test/FnameResolver/FnameResolverTestSuite.sol";
import "forge-std/console.sol";

/* solhint-disable state-visibility */

contract DeployL1Test is DeployL1, FnameResolverTestSuite {
    address internal deployer = address(this);
    address internal alpha = makeAddr("alpha");
    address internal alice = makeAddr("alice");

    function setUp() public override {
        vm.createSelectFork("eth_mainnet");

        (signer, signerPk) = makeAddrAndKey("signer");

        DeployL1.DeploymentParams memory params = DeployL1.DeploymentParams({
            serverURL: "https://fnames.farcaster.xyz/ccip/{sender}/{data}.json",
            signer: signer,
            owner: alpha,
            deployer: deployer
        });

        DeployL1.Contracts memory contracts = runDeploy(params, false);

        resolver = contracts.fnameResolver;
    }

    function test_deploymentParams() public {
        // Check deployment parameters
        assertEq(resolver.url(), "https://fnames.farcaster.xyz/ccip/{sender}/{data}.json");
        assertEq(resolver.owner(), alpha);
        assertEq(resolver.signers(signer), true);
    }

    function test_e2e() public {
        uint256 timestamp = block.timestamp - 60;
        bytes memory signature = _signProof(signerPk, "alice.fcast.id", timestamp, alice);
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes memory response =
            resolver.resolveWithProof(abi.encode("alice.fcast.id", timestamp, alice, signature), extraData);
        assertEq(response, abi.encode(alice));
    }
}
