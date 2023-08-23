// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {EIP712 as EIP712Base} from "openzeppelin/contracts/utils/cryptography/EIP712.sol";

abstract contract EIP712 is EIP712Base {
    constructor(string memory name, string memory version) EIP712Base(name, version) {}

    /*//////////////////////////////////////////////////////////////
                           EIP-712 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Helper view to read EIP-712 domain separator.
     *
     * @return bytes32 domain separator hash.
     */
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Helper view to hash EIP-712 typed data onchain.
     *
     * @param structHash EIP-712 typed data hash.
     *
     * @return bytes32 EIP-712 message digest.
     */
    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }
}
