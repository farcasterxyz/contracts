// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {KeyRegistry} from "../../src/KeyRegistry.sol";

library BulkAddDataBuilder {
    function empty() internal pure returns (KeyRegistry.BulkAddData[] memory) {
        return new KeyRegistry.BulkAddData[](0);
    }

    function addFid(
        KeyRegistry.BulkAddData[] memory addData,
        uint256 fid
    ) internal pure returns (KeyRegistry.BulkAddData[] memory) {
        KeyRegistry.BulkAddData[] memory newData = new KeyRegistry.BulkAddData[](addData.length + 1);
        for (uint256 i; i < addData.length; i++) {
            newData[i] = addData[i];
        }
        newData[addData.length].fid = fid;
        return newData;
    }

    function addFidsWithKeys(
        KeyRegistry.BulkAddData[] memory addData,
        uint256[] memory fids,
        bytes[][] memory keys
    ) internal pure returns (KeyRegistry.BulkAddData[] memory) {
        for (uint256 i; i < fids.length; ++i) {
            addData = addFid(addData, fids[i]);
            bytes[] memory fidKeys = keys[i];
            for (uint256 j; j < fidKeys.length; ++j) {
                addData = addKey(addData, i, fidKeys[j], bytes.concat("metadata-", fidKeys[j]));
            }
        }
        return addData;
    }

    function addKey(
        KeyRegistry.BulkAddData[] memory addData,
        uint256 index,
        bytes memory key,
        bytes memory metadata
    ) internal pure returns (KeyRegistry.BulkAddData[] memory) {
        KeyRegistry.BulkAddKey[] memory keys = addData[index].keys;
        KeyRegistry.BulkAddKey[] memory newKeys = new KeyRegistry.BulkAddKey[](keys.length + 1);

        for (uint256 i; i < keys.length; i++) {
            newKeys[i] = keys[i];
        }
        newKeys[keys.length].key = key;
        newKeys[keys.length].metadata = metadata;
        addData[index].keys = newKeys;
        return addData;
    }
}

library BulkResetDataBuilder {
    function empty() internal pure returns (KeyRegistry.BulkResetData[] memory) {
        return new KeyRegistry.BulkResetData[](0);
    }

    function addFid(
        KeyRegistry.BulkResetData[] memory resetData,
        uint256 fid
    ) internal pure returns (KeyRegistry.BulkResetData[] memory) {
        KeyRegistry.BulkResetData[] memory newData = new KeyRegistry.BulkResetData[](resetData.length + 1);
        for (uint256 i; i < resetData.length; i++) {
            newData[i] = resetData[i];
        }
        newData[resetData.length].fid = fid;
        return newData;
    }

    function addFidsWithKeys(
        KeyRegistry.BulkResetData[] memory resetData,
        uint256[] memory fids,
        bytes[][] memory keys
    ) internal pure returns (KeyRegistry.BulkResetData[] memory) {
        for (uint256 i; i < fids.length; ++i) {
            resetData = addFid(resetData, fids[i]);
            bytes[] memory fidKeys = keys[i];
            for (uint256 j; j < fidKeys.length; ++j) {
                resetData = addKey(resetData, i, fidKeys[j]);
            }
        }
        return resetData;
    }

    function addKey(
        KeyRegistry.BulkResetData[] memory resetData,
        uint256 index,
        bytes memory key
    ) internal pure returns (KeyRegistry.BulkResetData[] memory) {
        bytes[] memory prevKeys = resetData[index].keys;
        bytes[] memory newKeys = new bytes[](prevKeys.length + 1);

        for (uint256 i; i < prevKeys.length; i++) {
            newKeys[i] = prevKeys[i];
        }
        newKeys[prevKeys.length] = key;
        resetData[index].keys = newKeys;
        return resetData;
    }
}
