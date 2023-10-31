// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IMigration} from "../interfaces/lib/IMigration.sol";

abstract contract Migration is IMigration {
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
