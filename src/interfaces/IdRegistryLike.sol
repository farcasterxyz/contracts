// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @dev Minimal interface for IdRegistry, used by the KeyRegistry.
 */
interface IdRegistryLike {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maps each address to an fid, or zero if it does not own an fid.
     */
    function idOf(
        address fidOwner
    ) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verify that a signature was produced by the custody address that owns an fid.
     *
     * @param custodyAddress   The address to check the signature of.
     * @param fid              The fid to check the signature of.
     * @param digest           The digest that was signed.
     * @param sig              The signature to check.
     *
     * @return isValid Whether provided signature is valid.
     */
    function verifyFidSignature(
        address custodyAddress,
        uint256 fid,
        bytes32 digest,
        bytes calldata sig
    ) external view returns (bool isValid);
}
