// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IRegistration {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice EIP-712 typehash for Register signatures.
     */
    function REGISTER_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new Farcaster ID (fid) to the caller. The caller must not have an fid.
     *         The contract must not be in the Registrable (trustedOnly = 0) state.
     *
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     *
     * @return fid registered FID.
     */
    function register(address recovery) external returns (uint256 fid);

    /**
     * @notice Register a new Farcaster ID (fid) to any address. A signed message from the address
     *         must be provided which approves both the to and the recovery. The address must not
     *         have an fid. The contract must be in the Registrable (trustedOnly = 0) state.
     *
     * @param to       Address which will own the fid.
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Register signature signed by the to address.
     *
     * @return fid registered FID.
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external returns (uint256 fid);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new Farcaster ID (fid) to any address. The address must not have an fid.
     *         The contract must be in the Seedable (trustedOnly = 1) state.
     *         Can only be called by the trustedCaller.
     *
     * @param to       The address which will own the fid.
     * @param recovery The address which can recover the fid.
     *
     * @return fid registered FID.
     */
    function trustedRegister(address to, address recovery) external returns (uint256 fid);

    /**
     * @notice Pause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function pause() external;

    /**
     * @notice Unpause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function unpause() external;
}
