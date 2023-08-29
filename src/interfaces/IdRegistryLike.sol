// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IdRegistryLike {
    function idOf(address fidOwner) external view returns (uint256);

    function verifyFidSignature(
        address custodyAddress,
        uint256 fid,
        bytes32 digest,
        bytes calldata sig
    ) external view returns (bool isValid);
}
