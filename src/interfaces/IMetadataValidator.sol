// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IMetadataValidator {
    function validate(uint256 userFid, bytes memory key, bytes memory metadata) external returns (bool);
}
