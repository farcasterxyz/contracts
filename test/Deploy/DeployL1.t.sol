// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {DeployL1, FnameResolver} from "../../script/DeployL1.s.sol";
import {IResolverService} from "../../src/FnameResolver.sol";
import {FnameResolverTestSuite} from "../../test/FnameResolver/FnameResolverTestSuite.sol";
import "forge-std/console.sol";

/* solhint-disable state-visibility */

contract DeployL1Test is DeployL1, FnameResolverTestSuite {
    address internal deployer = address(this);
    address internal alpha = makeAddr("alpha");

    function setUp() public override {
        vm.createSelectFork("l1_mainnet");

        (signer, signerPk) = makeAddrAndKey("signer");

        DeployL1.DeploymentParams memory params = DeployL1.DeploymentParams({
            name: hex"096661726361737465720365746800",
            resolver: 0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63,
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
        assertEq(resolver.dnsEncodedName(), hex"096661726361737465720365746800");
        assertEq(address(resolver.passthroughResolver()), 0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63);
        assertEq(resolver.url(), "https://fnames.farcaster.xyz/ccip/{sender}/{data}.json");
        assertEq(resolver.owner(), alpha);
        assertEq(resolver.signers(signer), true);
    }

    function test_e2e() public {
        // calldata  of resolve()
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes32 requestHash = keccak256(extraData);
        uint256 expiration = block.timestamp + 60;
        bytes memory result = abi.encode(address(alpha));
        bytes memory signature = _signProof(signerPk, requestHash, result, expiration);
        bytes memory response =
            resolver.resolveWithProof(abi.encode(requestHash, result, expiration, signature), extraData);
        assertEq(response, result);
    }
}
