// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {StorageRegistryTestSuite} from "./StorageRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract StorageRegistryGasUsageTest is StorageRegistryTestSuite {
    function testGasRent() public {
        uint256 units = 1;
        uint256 price = storageRegistry.price(units);

        for (uint256 i = 0; i < 10; i++) {
            storageRegistry.rent{value: price}(i, units);
        }
    }

    function testGasBatchRent() public {
        uint256[] memory units = new uint256[](5);
        units[0] = 1;
        units[1] = 1;
        units[2] = 1;
        units[3] = 1;
        units[4] = 1;

        uint256[] memory ids = new uint256[](5);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;
        ids[4] = 5;

        uint256 totalCost = storageRegistry.price(5);
        vm.deal(address(this), totalCost * 10);

        for (uint256 i = 0; i < 10; i++) {
            storageRegistry.batchRent{value: totalCost}(ids, units);
        }
    }

    function testGasCredit() public {
        uint256 units = 1;

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(operator);
            storageRegistry.credit(1, units);
        }
    }

    function testGasBatchCredit() public {
        uint256[] memory ids = new uint256[](5);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;
        ids[4] = 5;

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(operator);
            storageRegistry.batchCredit(ids, 1);
        }
    }

    function testGasContinuousCredit() public {
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(operator);
            storageRegistry.continuousCredit(1, 5, 1);
        }
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
