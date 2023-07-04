// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Bundler} from "../../src/Bundler.sol";
import {BundlerTestSuite} from "./BundlerTestSuite.sol";

/* solhint-disable state-visibility */

contract BundleRegistryGasUsageTest is BundlerTestSuite {
    function testGasRegister() public {
        idRegistry.disableTrustedOnly();

        for (uint256 i = 0; i < 10; i++) {
            address account = address(uint160(i));
            uint256 price = storageRent.price(1);

            vm.deal(account, 10_000 ether);
            vm.prank(account);
            bundler.register{value: price}(account, address(0), 1);
        }
    }

    function testGasTrustedRegister() public {
        idRegistry.setTrustedCaller(address(bundler));

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        for (uint256 i = 0; i < 10; i++) {
            address account = address(uint160(i));

            bundler.trustedRegister(account, address(0), 1);
        }
    }

    function testGasTrustedBatchRegister() public {
        idRegistry.setTrustedCaller(address(bundler));

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        for (uint256 i = 0; i < 10; i++) {
            Bundler.UserData[] memory batchArray = new Bundler.UserData[](10);

            for (uint256 j = 0; j < 10; j++) {
                address account = address(uint160(((i * 10) + j + 1)));
                batchArray[j] = Bundler.UserData({to: account, units: 1, recovery: address(0)});
            }

            bundler.trustedBatchRegister(batchArray);
        }
    }
}
