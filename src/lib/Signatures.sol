// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ECDSA} from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract Signatures {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when the signature provided is invalid.
    error InvalidSignature();

    /// @dev Revert when the block.timestamp is ahead of the signature deadline.
    error SignatureExpired();

    /*//////////////////////////////////////////////////////////////
                     SIGNATURE VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifySig(bytes32 digest, address signer, uint256 deadline, bytes memory sig) internal view {
        if (block.timestamp >= deadline) revert SignatureExpired();
        address recovered = ECDSA.recover(digest, sig);
        if (recovered != signer) revert InvalidSignature();
    }
}
