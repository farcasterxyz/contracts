// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Nonces as NoncesBase} from "openzeppelin-latest/contracts/utils/Nonces.sol";

abstract contract Nonces is NoncesBase {
    /*//////////////////////////////////////////////////////////////
                          NONCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Increase caller's nonce, invalidating previous signatures.
     *
     */
    function useNonce() external returns (uint256) {
        return _useNonce(msg.sender);
    }
}
