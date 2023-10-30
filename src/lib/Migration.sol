// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IMigration} from "../interfaces/lib/IMigration.sol";

abstract contract Migration is IMigration {
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

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable migrator;

    uint24 public immutable gracePeriod;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint40 public migratedAt;

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier migration() {
        if (msg.sender != migrator) revert OnlyMigrator();
        if (isMigrated() && block.timestamp > migratedAt + gracePeriod) {
            revert PermissionRevoked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the grace period.
     *
     * @param _gracePeriod Migration grace period in seconds.
     * @param _migrator    Migration admin address.
     */
    constructor(uint24 _gracePeriod, address _migrator) {
        gracePeriod = _gracePeriod;
        migrator = _migrator;
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    function isMigrated() public view returns (bool) {
        return migratedAt != 0;
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    function migrate() external {
        if (msg.sender != migrator) revert OnlyMigrator();
        if (isMigrated()) revert AlreadyMigrated();
        migratedAt = uint40(block.timestamp);
        emit Migrated(migratedAt);
    }
}
