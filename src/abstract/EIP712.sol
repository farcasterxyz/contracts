// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {EIP712 as EIP712Base} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IEIP712} from "../interfaces/abstract/IEIP712.sol";

abstract contract EIP712 is IEIP712, EIP712Base {
    constructor(string memory name, string memory version) EIP712Base(name, version) {}

    /*//////////////////////////////////////////////////////////////
                           EIP-712 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEIP712
     */
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @inheritdoc IEIP712
     */
    function hashTypedDataV4(
        bytes32 structHash
    ) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }
}
