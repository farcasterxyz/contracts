// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Guardians} from "./Guardians.sol";
import {ITrustedCaller} from "../interfaces/lib/ITrustedCaller.sol";

abstract contract TrustedCaller is ITrustedCaller, Guardians {
    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITrustedCaller
     */
    address public trustedCaller;

    /**
     * @inheritdoc ITrustedCaller
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
     * @inheritdoc ITrustedCaller
     */
    function setTrustedCaller(address _trustedCaller) public onlyOwner {
        _setTrustedCaller(_trustedCaller);
    }

    /**
     * @inheritdoc ITrustedCaller
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
