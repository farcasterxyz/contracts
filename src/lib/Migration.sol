// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Guardians} from "../lib/Guardians.sol";
import {IMigration} from "../interfaces/lib/IMigration.sol";

abstract contract Migration is IMigration, Guardians {
    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

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
    address public migrator;

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
        _requirePaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the grace period and migrator address.
     *         Pauses contract at deployment time.
     *
     * @param _gracePeriod  Migration grace period in seconds.
     * @param _initialOwner Initial owner address. Set as migrator.
     */
    constructor(uint24 _gracePeriod, address _initialOwner) Guardians(_initialOwner) {
        gracePeriod = _gracePeriod;
        migrator = _initialOwner;
        _pause();
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
        _requirePaused();
        migratedAt = uint40(block.timestamp);
        emit Migrated(migratedAt);
    }

    /*//////////////////////////////////////////////////////////////
                              SET MIGRATOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the migrator address. Only callable by owner.
     *
     * @param _migrator The address of the new migrator
     */
    function setMigrator(address _migrator) public onlyOwner {
        emit SetMigrator(migrator, _migrator);
        migrator = _migrator;
    }
}
