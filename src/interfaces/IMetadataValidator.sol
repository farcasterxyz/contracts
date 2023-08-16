// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IMetadataValidator {
    function validate(uint256 userFid, bytes memory signerKey, bytes memory metadata) external returns (bool);
}
