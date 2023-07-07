// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {IdRegistry} from "./IdRegistry.sol";

contract KeyRegistry is Ownable2Step {
    /**
     *  @notice Authorization state enum for a signer.
     *          - UNINITIALIZED: The signer's key is not registered.
     *          - AUTHORIZED: The signer's is registered.
     *          - FROZEN: The signer's key was registered, but is now frozen.
     *          - REVOKED: The signer's key was registered, but is now revoked.
     */
    enum SignerState {
        UNINITIALIZED,
        AUTHORIZED,
        FROZEN,
        REVOKED
    }

    /**
     *  @notice Authorization state of a signer.
     *
     *  @param state      Authorization state of the signer.
     *  @param merkleRoot Merkle root of valid messages produced by the signer.
     *                    Used to freeze a signer but preserve past valid messages.
     */
    struct Signer {
        SignerState state;
        bytes32 merkleRoot;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @dev Revert if a register/revoke/freeze attempts an invalid state transition.
     *       - Register: key must be UNINITIALIZED.
     *       - Freeze: key must be AUTHORIZED.
     *       - Revoke: key must be AUTHORIZED or FROZEN.
     */
    error InvalidState();

    /// @dev Revert if owner attempts a bulk add/remove after the migration grace period.
    error Unauthorized();

    /// @dev Revert if owner calls migrateSigners more than once.
    error AlreadyMigrated();

    /// @dev Revert if migration batch input arrays are not the same length.
    error InvalidBatchInput();

    /// @dev Revert if a caller attempts to freeze a key without providing a merkle root.
    error InvalidMerkleRoot();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when an admin or FID registers a new key.
     *
     * @param fid       The fid associated with the key.
     * @param scope     The scope of the key.
     * @param key       The public key being registered. (indexed as hash)
     * @param keyBytes  The bytes of the public key being registered.
     */
    event Register(uint256 indexed fid, uint256 indexed scope, bytes indexed key, bytes keyBytes);

    /**
     * @dev Emit an event when an admin removes a new key.
     *
     * @param fid       The fid associated with the key.
     * @param scope     The scope of the key.
     * @param key       The public key being registered. (indexed as hash)
     * @param keyBytes  The bytes of the public key being registered.
     */
    event Remove(uint256 indexed fid, uint256 indexed scope, bytes indexed key, bytes keyBytes);

    /**
     * @dev Emit an event when an FID revokes a new key.
     *
     * @param fid       The fid revoking the key.
     * @param scope     The scope of the key.
     * @param key       The public key being registered. (indexed as hash)
     * @param keyBytes  The bytes of the public key being registered.
     */
    event Revoke(uint256 indexed fid, uint256 indexed scope, bytes indexed key, bytes keyBytes);

    /**
     * @dev Emit an event when an FID freezes a key.
     *
     * @param fid        The fid revoking the key.
     * @param scope      The scope of the key.
     * @param key        The public key being registered. (indexed as hash)
     * @param keyBytes   The bytes of the public key being registered.
     * @param merkleRoot The merkle root of valid messages produced by the signer.
     */
    event Freeze(uint256 indexed fid, uint256 indexed scope, bytes indexed key, bytes keyBytes, bytes32 merkleRoot);

    /**
     * @dev Emit an event when the admin calls migrateSigners.
     */
    event SignersMigrated();

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The IdRegistry contract.
     */
    IdRegistry public immutable idRegistry;

    /**
     * @dev Period in seconds after migration during which admin can bulk add/remove signers.
     *      This grace period allows the admin to make corrections to the migrated data during
     *      the grace period if necessary, but prevents any changes after it expires.
     */
    uint24 public immutable gracePeriod;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Timestamp at which signer data was migrated. Hubs will cut over to use the onchain
     *      registry as their source of truth after this timestamp.
     */
    uint40 public signersMigratedAt;

    /**
     * @dev Mapping of FID to scope to key to signer state.
     *
     * @custom:param fid    The fid associated with the key.
     * @custom:param scope  The key's scope. In the initial migration all keys will have scope 1.
     * @custom:param key    Bytes of the signer's public key.
     * @custom:param signer Signer struct including state and merkle root for frozen signers.
     */
    mapping(uint256 fid => mapping(uint256 scope => mapping(bytes key => Signer signer))) public signers;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the IdRegistry, migration grace period, and owner.
     *
     * @param _idRegistry  IdRegistry contract address. Immutable.
     * @param _gracePeriod Migration grace period in seconds. Immutable.
     * @param _owner       Contract owner address.
     */
    constructor(address _idRegistry, uint24 _gracePeriod, address _owner) {
        _transferOwnership(_owner);

        gracePeriod = _gracePeriod;
        idRegistry = IdRegistry(_idRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Revert if caller does not own the associated fid.
     */
    modifier onlyFidOwner(uint256 fid) {
        if (idRegistry.idOf(msg.sender) != fid) revert Unauthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieve signer state for a fid/scope/key tuple.
     *
     * @param fid   The fid associated with the key.
     * @param scope The key's numeric scope. In the initial migration all keys will have scope 1.
     * @param key   Bytes of the signer's public key.
     *
     * @return Signer struct including state and message merkle root for frozen signers.
     */
    function signerOf(uint256 fid, uint256 scope, bytes calldata key) external view returns (Signer memory) {
        return signers[fid][scope][key];
    }

    /**
     * @notice Check if the contract has been migrated.
     *
     * @return true if the contract has been migrated, false otherwise.
     */
    function isMigrated() public view returns (bool) {
        return signersMigratedAt != 0;
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL KEY REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a public key to a fid/scope pair, setting the signer state to AUTHORIZED.
     *
     * @param fid   The fid associated with the key. Caller must own the provided fid.
     * @param scope The key's numeric scope.
     * @param key   Bytes of the signer's public key to authorize.
     */
    function register(uint256 fid, uint256 scope, bytes calldata key) external onlyFidOwner(fid) {
        _register(fid, scope, key);
    }

    /**
     * @notice Revoke a public key associated with a fid/scope pair, setting the signer state to REVOKED.
     *         The key must be in the AUTHORIZED or FROZEN state.
     *
     * @param fid   The fid associated with the key. Caller must own the provided fid.
     * @param scope The key's numeric scope.
     * @param key   Bytes of the signer's public key to revoke.
     */
    function revoke(uint256 fid, uint256 scope, bytes calldata key) external onlyFidOwner(fid) {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.AUTHORIZED && signer.state != SignerState.FROZEN) revert InvalidState();

        signer.state = SignerState.REVOKED;
        emit Revoke(fid, scope, key, key);
    }

    /**
     * @notice Freeze a public key associated with a fid/scope pair, setting the signer state to FROZEN.
     *         The key must be in the AUTHORIZED state. Freezing a key will retain past valid messages
     *         signed by the key, while revoking a key will delete them. Caller must provide a merkle root
     *         of valid messages produced by the signer.
     *
     * @param fid        The fid associated with the key. Caller must own the provided fid.
     * @param scope      The key's numeric scope.
     * @param key        Bytes of the signer's public key to freeze.
     * @param merkleRoot The merkle root of valid messages produced by the signer.
     */
    function freeze(uint256 fid, uint256 scope, bytes calldata key, bytes32 merkleRoot) external onlyFidOwner(fid) {
        if (merkleRoot == bytes32(0)) revert InvalidMerkleRoot();
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.AUTHORIZED) revert InvalidState();

        signer.state = SignerState.FROZEN;
        signer.merkleRoot = merkleRoot;
        emit Freeze(fid, scope, key, key, merkleRoot);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIAL MIGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the time of the signer migration and emit an event. Hubs will watch this event and
     *         cut over to use the onchain registry as their source of truth after this timestamp.
     *         Only callable by the contract owner.
     */
    function migrateSigners() external onlyOwner {
        if (isMigrated()) revert AlreadyMigrated();
        signersMigratedAt = uint40(block.timestamp);
        emit SignersMigrated();
    }

    /**
     * @notice Register multiple signers as part of the initial migration. Only callable by the contract owner.
     *
     * @param fids  A list of fids to associate with keys.
     * @param keys  A list of public keys to register for each fid, in the same order as the fids array.
     */
    function bulkAddSignersForMigration(uint256[] calldata fids, bytes[][] calldata keys) external onlyOwner {
        if (isMigrated() && block.timestamp > signersMigratedAt + gracePeriod) revert Unauthorized();
        if (fids.length != keys.length) revert InvalidBatchInput();

        unchecked {
            for (uint256 i = 0; i < fids.length; i++) {
                uint256 fid = fids[i];
                for (uint256 j = 0; j < keys[i].length; j++) {
                    _register(fid, 1, keys[i][j]);
                }
            }
        }
    }

    /**
     * @notice Remove multiple signers as part of the initial migration. Only callable by the contract owner.
     *         Removal is not the same as revocation: this function sets the signer state back to UNINITIALIZED,
     *         rather than REVOKED. This allows the owner to correct any errors in the initial migration until
     *         the grace period expires.
     *
     * @param fids  A list of fids to whose registered keys should be removed.
     * @param keys  A list of public keys to remove for each fid, in the same order as the fids array.
     */
    function bulkRemoveSignersForMigration(uint256[] calldata fids, bytes[][] calldata keys) external onlyOwner {
        if (isMigrated() && block.timestamp > signersMigratedAt + uint40(gracePeriod)) revert Unauthorized();
        if (fids.length != keys.length) revert InvalidBatchInput();

        unchecked {
            for (uint256 i = 0; i < fids.length; i++) {
                uint256 fid = fids[i];
                for (uint256 j = 0; j < keys[i].length; j++) {
                    _remove(fid, 1, keys[i][j]);
                }
            }
        }
    }

    function _register(uint256 fid, uint256 scope, bytes calldata key) internal {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.UNINITIALIZED) revert InvalidState();

        signer.state = SignerState.AUTHORIZED;
        emit Register(fid, scope, key, key);
    }

    function _remove(uint256 fid, uint256 scope, bytes calldata key) internal {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.AUTHORIZED && signer.state != SignerState.FROZEN) revert InvalidState();

        signer.state = SignerState.UNINITIALIZED;
        emit Remove(fid, scope, key, key);
    }
}
