// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import {Bundler, IBundler} from "../../src/Bundler.sol";
import {BundlerTestSuite} from "./BundlerTestSuite.sol";

/* solhint-disable state-visibility */

contract BundleRegistryGasUsageTest is BundlerTestSuite {
    function setUp() public override {
        super.setUp();
        _registerValidator(1, 1);
    }

    function testGasRegisterWithSig() public {
        vm.prank(owner);
        idManager.disableTrustedOnly();

        for (uint256 i = 1; i < 10; i++) {
            address account = vm.addr(i);
            bytes memory sig = _signRegister(i, account, address(0), type(uint40).max);
            uint256 price = storageRegistry.price(2);

            IBundler.SignerParams[] memory signers = new IBundler.SignerParams[](
                0
            );

            vm.deal(account, 10_000 ether);
            vm.prank(account);
            bundler.register{value: price}(
                IBundler.RegistrationParams({to: account, recovery: address(0), deadline: type(uint40).max, sig: sig}),
                signers,
                1
            );
        }
    }

    function testGasTrustedBatchRegister() public {
        vm.prank(owner);
        idManager.setTrustedCaller(address(bundler));

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        for (uint256 i = 0; i < 10; i++) {
            IBundler.UserData[] memory batchArray = new IBundler.UserData[](10);

            for (uint256 j = 0; j < 10; j++) {
                address account = address(uint160(((i * 10) + j + 1)));
                batchArray[j] = IBundler.UserData({to: account, recovery: address(0)});
            }

            bundler.trustedBatchRegister(batchArray);
        }
    }
}
