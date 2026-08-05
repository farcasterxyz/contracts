// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title ISnapchainConfigRegistry
 *
 * @notice Interface for the SnapchainConfigRegistry contract, which holds the canonical validator
 *         sets and gossip peer lists for a Snapchain network.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
interface ISnapchainConfigRegistry {
    /**
     * @notice One validator set, effective from a given Snapchain block height onward.
     *
     * @param effectiveAt          Snapchain block height at which this set becomes active. This is a
     *                             Snapchain height, not an EVM block number and not a timestamp.
     *                             Nothing onchain can validate it.
     * @param shardIds             Shards this set governs. 0 is the block shard, 1 and above are
     *                             message shards.
     * @param validatorPublicKeys  Ed25519 public keys of the validators in this set. Stored as
     *                             bytes32 rather than hex strings so that rendering can only ever
     *                             emit characters from a fixed hex alphabet.
     */
    struct ValidatorSet {
        uint64 effectiveAt;
        uint32[] shardIds;
        bytes32[] validatorPublicKeys;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if shardIds is empty, exceeds MAX_SHARD_IDS, or contains a duplicate.
    error InvalidShardIds();

    /// @dev Revert if validatorPublicKeys is empty, exceeds MAX_VALIDATOR_PUBLIC_KEYS, or contains
    ///      a zero or duplicate key.
    error InvalidValidatorPublicKeys();

    /// @dev Revert if effectiveAt is lower than that of the most recent preceding validator set
    ///      governing a shard in common. Entries governing disjoint shards are unconstrained
    ///      relative to one another, since each shard's height is an independent counter.
    error InvalidEffectiveAt();

    /// @dev Revert if the caller amends or removes the latest validator set while there are none.
    error NoValidatorSets();

    /// @dev Revert if a peer string exceeds MAX_PEER_STRING_LENGTH or contains a byte outside the
    ///      allowlist. See the "TOML injection" section of docs/snapchain-config-registry.md.
    error InvalidPeerString();

    /// @dev Revert if a validator set index or range falls outside the stored array.
    error InvalidRange();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a validator set is appended.
     * @dev Carries the full payload so an indexer can reconstruct the rendered document from logs
     *      alone, with no archive-node call per historical block.
     * @param index                Index of the appended set.
     * @param effectiveAt          Snapchain block height at which the set becomes active.
     * @param shardIds             Shards this set governs.
     * @param validatorPublicKeys  Ed25519 public keys in the set.
     * @param configVersion        Registry version after this change.
     */
    event AppendValidatorSet(
        uint256 indexed index,
        uint64 indexed effectiveAt,
        uint32[] shardIds,
        bytes32[] validatorPublicKeys,
        uint256 configVersion
    );

    /**
     * @notice Emitted when the latest validator set is amended in place.
     * @param index                Index of the amended set.
     * @param effectiveAt          Snapchain block height at which the set becomes active.
     * @param shardIds             Shards this set governs.
     * @param validatorPublicKeys  Ed25519 public keys in the set.
     * @param configVersion        Registry version after this change.
     */
    event AmendValidatorSet(
        uint256 indexed index,
        uint64 indexed effectiveAt,
        uint32[] shardIds,
        bytes32[] validatorPublicKeys,
        uint256 configVersion
    );

    /**
     * @notice Emitted when the latest validator set is removed.
     * @param index         Index the removed set occupied.
     * @param configVersion Registry version after this change.
     */
    event RemoveValidatorSet(uint256 indexed index, uint256 configVersion);

    /**
     * @notice Emitted when the bootstrap peer list is set.
     * @param oldPeers      Previous value.
     * @param newPeers      New value.
     * @param configVersion Registry version after this change.
     */
    event SetBootstrapPeers(string oldPeers, string newPeers, uint256 configVersion);

    /**
     * @notice Emitted when the direct peer list is set.
     * @param oldPeers      Previous value.
     * @param newPeers      New value.
     * @param configVersion Registry version after this change.
     */
    event SetDirectPeers(string oldPeers, string newPeers, uint256 configVersion);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice Maximum number of shard ids in a single validator set.
     */
    function MAX_SHARD_IDS() external view returns (uint256);

    /**
     * @notice Maximum number of public keys in a single validator set.
     */
    function MAX_VALIDATOR_PUBLIC_KEYS() external view returns (uint256);

    /**
     * @notice Maximum length in bytes of either peer string.
     */
    function MAX_PEER_STRING_LENGTH() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Counter incremented by exactly one on every mutation.
     * @dev Lets a poller detect change with one cheap call instead of fetching and diffing the whole
     *      rendered document. Starts at zero, so a client whose watermark starts at zero correctly
     *      treats deploy-time seeding as a change.
     */
    function configVersion() external view returns (uint256);

    /**
     * @notice Comma-separated multiaddrs a node dials on startup. May be empty.
     */
    function bootstrapPeers() external view returns (string memory);

    /**
     * @notice Comma-separated peer ids a node maintains direct connections to. May be empty.
     */
    function directPeers() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Number of stored validator sets.
     */
    function validatorSetCount() external view returns (uint256);

    /**
     * @notice Get one validator set by index.
     * @param index Index of the set to read.
     * @return The validator set at that index.
     */
    function validatorSetAt(
        uint256 index
    ) external view returns (ValidatorSet memory);

    /**
     * @notice Get every stored validator set, in order.
     */
    function validatorSets() external view returns (ValidatorSet[] memory);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Append a validator set. Only callable by owner.
     * @dev effectiveAt must be greater than or equal to that of the most recent preceding set
     *      governing a shard in common; sets over disjoint shards are unconstrained relative to one
     *      another, because each shard's height is an independent counter. Equality is permitted
     *      because per-shard rollouts legitimately land at the same height.
     * @param effectiveAt          Snapchain block height at which the set becomes active.
     * @param shardIds             Shards this set governs.
     * @param validatorPublicKeys  Ed25519 public keys in the set.
     */
    function appendValidatorSet(
        uint64 effectiveAt,
        uint32[] calldata shardIds,
        bytes32[] calldata validatorPublicKeys
    ) external;

    /**
     * @notice Overwrite the latest validator set in place. Only callable by owner.
     * @dev History is append-only; only the tip may be amended. The same per-shard effectiveAt
     *      bound against the preceding entries applies.
     * @param effectiveAt          Snapchain block height at which the set becomes active.
     * @param shardIds             Shards this set governs.
     * @param validatorPublicKeys  Ed25519 public keys in the set.
     */
    function amendLatestValidatorSet(
        uint64 effectiveAt,
        uint32[] calldata shardIds,
        bytes32[] calldata validatorPublicKeys
    ) external;

    /**
     * @notice Drop the latest validator set. Only callable by owner.
     * @dev Amending can only replace the tip with some other valid entry; there is no value meaning
     *      "no entry". Since the owner can already rewrite the tip's contents, refusing to let them
     *      delete it would be false rigor. The removal is still recorded as an event.
     */
    function removeLatestValidatorSet() external;

    /**
     * @notice Set the bootstrap peer list. Only callable by owner.
     * @param peers Comma-separated multiaddrs, or the empty string.
     */
    function setBootstrapPeers(
        string calldata peers
    ) external;

    /**
     * @notice Set the direct peer list. Only callable by owner.
     * @param peers Comma-separated peer ids, or the empty string.
     */
    function setDirectPeers(
        string calldata peers
    ) external;
}
