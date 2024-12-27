// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IEIP712 {
    /*//////////////////////////////////////////////////////////////
                           EIP-712 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Helper view to read EIP-712 domain separator.
     *
     * @return bytes32 domain separator hash.
     */
    function domainSeparatorV4() external view returns (bytes32);

    /**
     * @notice Helper view to hash EIP-712 typed data onchain.
     *
     * @param structHash EIP-712 typed data hash.
     *
     * @return bytes32 EIP-712 message digest.
     */
    function hashTypedDataV4(
        bytes32 structHash
    ) external view returns (bytes32);
}
