// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Guardians} from "./Guardians.sol";

abstract contract TrustedCaller is Guardians {
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
     * @dev The privileged address that is allowed to call trusted functions.
     */
    address public trustedCaller;

    /**
     * @dev Allows calling trusted functions when set 1, and disables trusted
     *      functions when set to 0. The value is set to 1 and can be changed to 0,
     *      but never back to 1.
     */
    uint256 public trustedOnly = 1;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allow only the trusted caller to call the modified function.
     */
    modifier onlyTrustedCaller() {
        if (trustedOnly == 0) revert Registrable();
        if (msg.sender != trustedCaller) revert OnlyTrustedCaller();
        _;
    }

    /**
     * @dev Prevent calling the modified function in trustedOnly mode.
     */
    modifier whenNotTrusted() {
        if (trustedOnly == 1) revert Seedable();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _initialOwner Initial contract owner address.
     */
    constructor(address _initialOwner) Guardians(_initialOwner) {}

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the trusted caller by calling this from the contract's owner.
     *
     * @param _trustedCaller The address of the new trusted caller
     */
    function setTrustedCaller(address _trustedCaller) public onlyOwner {
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Disable trustedOnly mode. Must be called by the contract's owner.
     */
    function disableTrustedOnly() external onlyOwner {
        delete trustedOnly;
        emit DisableTrustedOnly();
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal helper to set trusted caller. Can be used internally
     *      to set the trusted caller at construction time.
     */
    function _setTrustedCaller(address _trustedCaller) internal {
        if (_trustedCaller == address(0)) revert InvalidAddress();

        emit SetTrustedCaller(trustedCaller, _trustedCaller, msg.sender);
        trustedCaller = _trustedCaller;
    }
}
