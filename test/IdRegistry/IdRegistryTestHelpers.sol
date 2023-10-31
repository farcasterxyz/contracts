// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IIdRegistry} from "../../src/interfaces/IIdRegistry.sol";

library BulkRegisterDataBuilder {
    function empty() internal pure returns (IIdRegistry.BulkRegisterData[] memory) {
        return new IIdRegistry.BulkRegisterData[](0);
    }

    function addFid(
        IIdRegistry.BulkRegisterData[] memory addData,
        uint24 fid
    ) internal pure returns (IIdRegistry.BulkRegisterData[] memory) {
        IIdRegistry.BulkRegisterData[] memory newData = new IIdRegistry.BulkRegisterData[](addData.length + 1);
        for (uint256 i; i < addData.length; i++) {
            newData[i] = addData[i];
        }
        newData[addData.length].fid = fid;
        newData[addData.length].custody = address(uint160(uint256(keccak256(abi.encodePacked(fid)))));
        newData[addData.length].recovery =
            address(uint160(uint256(keccak256(abi.encodePacked(keccak256(abi.encodePacked(fid)))))));
        return newData;
    }
}
