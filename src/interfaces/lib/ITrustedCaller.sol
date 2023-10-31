// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface ITrustedCaller {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when an unauthorized caller calls a trusted function.
    error OnlyTrustedCaller();

    /// @dev Revert if trustedRegister is invoked after trustedCallerOnly is disabled.
    error Registrable();

    /// @dev Revert if register is invoked before trustedCallerOnly is disabled.
    error Seedable();

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the trusted caller is modified.
     *
     * @param oldCaller The address of the old trusted caller.
     * @param newCaller The address of the new trusted caller.
     * @param owner     The address of the owner setting the new caller.
     */
    event SetTrustedCaller(address indexed oldCaller, address indexed newCaller, address owner);

    /**
     * @dev Emit an event when the trustedOnly state is disabled.
     */
    event DisableTrustedOnly();

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The privileged address that is allowed to call trusted functions.
     */
    function trustedCaller() external returns (address);

    /**
     * @dev Allows calling trusted functions when set 1, and disables trusted
     *      functions when set to 0. The value is set to 1 and can be changed to 0,
     *      but never back to 1.
     */
    function trustedOnly() external returns (uint256);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the trusted caller by calling this from the contract's owner.
     *
     * @param _trustedCaller The address of the new trusted caller
     */
    function setTrustedCaller(address _trustedCaller) external;

    /**
     * @notice Disable trustedOnly mode. Must be called by the contract's owner.
     */
    function disableTrustedOnly() external;
}
