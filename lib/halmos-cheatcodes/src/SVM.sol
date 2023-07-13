// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/// @notice Symbolic Virtual Machine
interface SVM {
    // Create a new symbolic uint value ranging over [0, 2**bitSize - 1] (inclusive)
    function createUint(uint256 bitSize, string memory name) external returns (uint256 value);

    // Create a new symbolic byte array with the given byte size
    function createBytes(uint256 byteSize, string memory name) external returns (bytes memory value);

    // Create a new symbolic uint256 value
    function createUint256(string memory name) external returns (uint256 value);

    // Create a new symbolic bytes32 value
    function createBytes32(string memory name) external returns (bytes32 value);

    // Create a new symbolic address value
    function createAddress(string memory name) external returns (address value);

    // Create a new symbolic boolean value
    function createBool(string memory name) external returns (bool value);
}
