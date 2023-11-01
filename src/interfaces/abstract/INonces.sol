// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface INonces {
    /*//////////////////////////////////////////////////////////////
                          NONCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Increase caller's nonce, invalidating previous signatures.
     *
     * @return uint256 The caller's new nonce.
     */
    function useNonce() external returns (uint256);
}
