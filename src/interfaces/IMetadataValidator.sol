// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IMetadataValidator {
    /**
     * @notice Validate metadata associated with a key.
     *
     * @param userFid      The fid associated with the key.
     * @param key          Bytes of the key.
     * @param metadata     Metadata about the key.
     *
     * @return bool Whether the provided key and metadata are valid.
     */
    function validate(uint256 userFid, bytes memory key, bytes memory metadata) external returns (bool);
}
