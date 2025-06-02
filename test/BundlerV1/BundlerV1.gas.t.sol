// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import {BundlerV1, IBundlerV1} from "../../src/BundlerV1.sol";
import {BundlerV1TestSuite} from "./BundlerV1TestSuite.sol";

/* solhint-disable state-visibility */

contract BundleRegistryGasUsageTest is BundlerV1TestSuite {
    function setUp() public override {
        super.setUp();
        _registerValidator(1, 1);
    }

    function testGasRegisterWithSig() public {
        for (uint256 i = 1; i < 10; i++) {
            address account = vm.addr(i);
            bytes memory sig = _signRegister(i, account, address(0), type(uint40).max);
            uint256 price = bundler.price(1);

            IBundlerV1.SignerParams[] memory signers = new IBundlerV1.SignerParams[](0);

            vm.deal(account, 10_000 ether);
            vm.prank(account);
            bundler.register{value: price}(
                IBundlerV1.RegistrationParams({to: account, recovery: address(0), deadline: type(uint40).max, sig: sig}),
                signers,
                1
            );
        }
    }
}
