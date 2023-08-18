// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import {Bundler} from "../../src/Bundler.sol";
import {BundlerTestSuite, StorageRegistryTestSuite, KeyRegistryTestSuite} from "./BundlerTestSuite.sol";

/* solhint-disable state-visibility */

contract BundleRegistryGasUsageTest is BundlerTestSuite {
    function setUp() public override {
        super.setUp();
        _registerValidator(1, 1);
    }

    function testGasRegisterWithSig() public {
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        for (uint256 i = 1; i < 10; i++) {
            address account = vm.addr(i);
            bytes memory sig = _signRegister(i, account, address(0), type(uint40).max);
            uint256 price = storageRegistry.price(1);

            Bundler.SignerParams[] memory signers = new Bundler.SignerParams[](
                0
            );

            vm.deal(account, 10_000 ether);
            vm.prank(account);
            bundler.register{value: price}(
                Bundler.RegistrationParams({to: account, recovery: address(0), deadline: type(uint40).max, sig: sig}),
                signers,
                1
            );
        }
    }

    function testGasTrustedRegister() public {
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        for (uint256 i = 0; i < 10; i++) {
            address account = address(uint160(i));
            Bundler.SignerData[] memory signers = new Bundler.SignerData[](1);
            signers[0] = Bundler.SignerData({keyType: 1, key: "key", metadataType: 1, metadata: "metadata"});

            bundler.trustedRegister(Bundler.UserData({to: account, recovery: address(0), signers: signers, units: 1}));
        }
    }

    function testGasTrustedBatchRegister() public {
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        for (uint256 i = 0; i < 10; i++) {
            Bundler.UserData[] memory batchArray = new Bundler.UserData[](10);

            for (uint256 j = 0; j < 10; j++) {
                address account = address(uint160(((i * 10) + j + 1)));
                Bundler.SignerData[] memory signers = new Bundler.SignerData[](
                    1
                );
                signers[0] = Bundler.SignerData({keyType: 1, key: "key", metadataType: 1, metadata: "metadata"});
                batchArray[j] = Bundler.UserData({to: account, recovery: address(0), signers: signers, units: 1});
            }

            bundler.trustedBatchRegister(batchArray);
        }
    }
}
