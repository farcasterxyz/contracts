// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {DeployL1, FnameResolver} from "../../script/DeployL1.s.sol";
import {IResolverService} from "../../src/FnameResolver.sol";
import {FnameResolverTestSuite} from "../../test/FnameResolver/FnameResolverTestSuite.sol";
import "forge-std/console.sol";

/* solhint-disable state-visibility */

contract DeployL1Test is DeployL1, FnameResolverTestSuite {
    FnameResolver internal fnameResolver;

    address internal deployer = address(this);
    address internal alpha = makeAddr("alpha");
    address internal alice = makeAddr("alice");

    function setUp() public override {
        vm.createSelectFork("l1_mainnet");

        (signer, signerPk) = makeAddrAndKey("signer");

        DeployL1.DeploymentParams memory params = DeployL1.DeploymentParams({
            serverURL: "https://fnames.farcaster.xyz/ccip/{sender}/{data}.json",
            signer: signer,
            owner: alpha,
            deployer: deployer
        });

        DeployL1.Contracts memory contracts = runDeploy(params, false);

        fnameResolver = contracts.fnameResolver;
    }

    function test_deploymentParams() public {
        // Check deployment parameters
        assertEq(fnameResolver.url(), "https://fnames.farcaster.xyz/ccip/{sender}/{data}.json");
        assertEq(fnameResolver.owner(), alpha);
        assertEq(fnameResolver.signers(signer), true);
    }

    function test_e2e() public {
        uint256 timestamp = block.timestamp - 60;
        bytes memory signature = _signProof(signerPk, "alice.fcast.id", timestamp, alice);
        bytes memory extraData = abi.encodeCall(IResolverService.resolve, (DNS_ENCODED_NAME, ADDR_QUERY_CALLDATA));
        bytes memory response =
            fnameResolver.resolveWithProof(abi.encode("alice.fcast.id", timestamp, alice, signature), extraData);
        assertEq(response, abi.encode(alice));
    }

    function _signProof(
        uint256 pk,
        string memory name,
        uint256 timestamp,
        address owner
    ) internal returns (bytes memory signature) {
        bytes32 eip712hash = fnameResolver.hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("UserNameProof(string name,uint256 timestamp,address owner)"),
                    keccak256(bytes(name)),
                    timestamp,
                    owner
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, eip712hash);
        signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
    }
}
