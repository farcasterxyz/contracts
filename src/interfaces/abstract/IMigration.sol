// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IGuardians} from "./IGuardians.sol";

interface IMigration is IGuardians {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller is not the migrator.
    error OnlyMigrator();

    /// @dev Revert if the migrator calls a migration function after the grace period.
    error PermissionRevoked();

    /// @dev Revert if the migrator calls migrate more than once.
    error AlreadyMigrated();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the admin calls migrate(). Used to migrate
     *      Hubs from reading events from one contract to another.
     *
     * @param migratedAt  The timestamp at which the migration occurred.
     */
    event Migrated(uint256 indexed migratedAt);

    /**
     * @notice Emit an event when the owner changes the migrator address.
     *
     * @param oldMigrator The address of the previous migrator.
     * @param newMigrator The address of the new migrator.
     */
    event SetMigrator(address oldMigrator, address newMigrator);

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Period in seconds after migration during which admin can continue to call protected
     *         migration functions. Admins can make corrections to the migrated data during the
     *         grace period if necessary, but cannot make changes after it expires.
     */
    function gracePeriod() external view returns (uint24);

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Migration admin address.
     */
    function migrator() external view returns (address);

    /**
     * @notice Timestamp at which data is migrated. Hubs will cut over to use this contract as their
     *         source of truth after this timestamp.
     */
    function migratedAt() external view returns (uint40);

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if the contract has been migrated.
     *
     * @return true if the contract has been migrated, false otherwise.
     */
    function isMigrated() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the time of the migration and emit an event. Hubs will watch this event and
     *         cut over to use this contract as their source of truth after this timestamp.
     *         Only callable by the migrator.
     */
    function migrate() external;

    /**
     * @notice Set the migrator address. Only callable by owner.
     *
     * @param _migrator Migrator address.
     */
    function setMigrator(
        address _migrator
    ) external;
}
