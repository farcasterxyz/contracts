// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Nonces as NoncesBase} from "openzeppelin-latest/contracts/utils/Nonces.sol";
import {INonces} from "../interfaces/abstract/INonces.sol";

abstract contract Nonces is INonces, NoncesBase {
    /*//////////////////////////////////////////////////////////////
                          NONCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INonces
     */
    function useNonce() external returns (uint256) {
        return _useNonce(msg.sender);
    }
}
