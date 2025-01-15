// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IGuardians {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when owner adds a new guardian address.
     *
     * @param guardian Address of the added guardian.
     */
    event Add(address indexed guardian);

    /**
     * @dev Emit an event when owner removes a guardian address.
     *
     * @param guardian Address of the removed guardian.
     */
    event Remove(address indexed guardian);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if an unauthorized caller calls a protected function.
    error OnlyGuardian();

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add an address as a guardian. Only callable by owner.
     *
     * @param guardian Address of the guardian.
     */
    function addGuardian(
        address guardian
    ) external;

    /**
     * @notice Remove a guardian. Only callable by owner.
     *
     * @param guardian Address of the guardian.
     */
    function removeGuardian(
        address guardian
    ) external;

    /**
     * @notice Pause the contract. Only callable by owner or a guardian.
     */
    function pause() external;

    /**
     * @notice Unpause the contract. Only callable by owner.
     */
    function unpause() external;
}
