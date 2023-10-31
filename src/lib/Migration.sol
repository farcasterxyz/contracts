// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IMigration} from "../interfaces/lib/IMigration.sol";

abstract contract Migration is IMigration {
    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IMigration
     */
    address public immutable migrator;

    /**
     * @inheritdoc IMigration
     */
    uint24 public immutable gracePeriod;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IMigration
     */
    uint40 public migratedAt;

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow only the migrator to call the protected function.
     *         Revoke permissions after the migration period.
     */
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
     * @notice Set the grace period and migrator address.
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

    /**
     * @inheritdoc IMigration
     */
    function isMigrated() public view returns (bool) {
        return migratedAt != 0;
    }

    /*//////////////////////////////////////////////////////////////
                                MIGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IMigration
     */
    function migrate() external {
        if (msg.sender != migrator) revert OnlyMigrator();
        if (isMigrated()) revert AlreadyMigrated();
        migratedAt = uint40(block.timestamp);
        emit Migrated(migratedAt);
    }
}
