// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import {ISnapchainConfigRegistry} from "./interfaces/ISnapchainConfigRegistry.sol";

/**
 * @title SnapchainConfigRegistry
 *
 * @notice Canonical, owner-governed record of a Snapchain network's validator sets and gossip peer
 *         lists. Validator-set history is append-only: earlier entries are immutable, and only the
 *         latest may be amended or removed. Peer lists are plain settable strings.
 *
 * @notice See https://github.com/farcasterxyz/contracts/blob/main/docs/snapchain-config-registry.md
 *         for the schema and the rendered-output specification.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract SnapchainConfigRegistry is ISnapchainConfigRegistry, Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    string public constant VERSION = "2026.08.04";

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    uint256 public constant MAX_SHARD_IDS = 16;

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    uint256 public constant MAX_VALIDATOR_PUBLIC_KEYS = 128;

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    uint256 public constant MAX_PEER_STRING_LENGTH = 8192;

    /**
     * @dev Allowlist of bytes permitted in a peer string, as a bitmap over 0x00-0x3F. Bit i is set
     *      if byte i is allowed. Covers space, comma, hyphen, period, slash, the digits, and colon.
     *
     *      Anything a multiaddr or base58 peer id can contain is here; nothing else is. In
     *      particular the quote and backslash are excluded, which is what makes it impossible for a
     *      peer string to escape the TOML literal it is rendered into.
     */
    uint256 internal constant _PEER_CHARS_LO = 0x07FFF00100000000;

    /**
     * @dev Allowlist bitmap over 0x40-0x7F; bit i is set if byte (0x40 + i) is allowed. Covers the
     *      uppercase letters, underscore, and the lowercase letters.
     */
    uint256 internal constant _PEER_CHARS_HI = 0x07FFFFFE87FFFFFE;

    /**
     * @dev Lowercase hex alphabet, left-aligned in a word so that a nibble indexes it directly via
     *      the `byte` opcode, which counts from the most significant byte.
     */
    uint256 internal constant _HEX_SYMBOLS_ALIGNED = 0x3031323334353637383961626364656600000000000000000000000000000000;

    /**
     * @dev Bytes in one rendered key line: two spaces, a quote, 64 hex characters, a quote, a
     *      comma, and a newline.
     */
    uint256 internal constant _KEY_LINE_LENGTH = 70;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Validator sets in append order. Held internal with explicit accessors because the
     *      compiler-generated getter for an array of structs with nested dynamic arrays returns
     *      only the value-type members.
     */
    ValidatorSet[] internal _validatorSets;

    /**
     * @dev Highest `effectiveAt` across every stored set governing each shard.
     *
     *      Because a set's `effectiveAt` is bounded below by this value at write time, the running
     *      value is both the maximum and the most recent, which is what the bound in §2.3 of
     *      docs/snapchain-config-registry.md is defined against. Zero for a shard no set governs,
     *      which correctly imposes no bound.
     */
    mapping(uint32 shardId => uint64 effectiveAt) internal _lastEffectiveAt;

    /**
     * @dev For each stored set, the value `_lastEffectiveAt` held for each of that set's shards
     *      immediately before the set was written, positionally aligned with its `shardIds`.
     *
     *      This is what makes the tip mutable in constant time. Amending or removing a set has to
     *      undo that set's contribution to `_lastEffectiveAt` before the bound can be re-evaluated
     *      against the sets preceding it, and the contribution is not otherwise recoverable: the
     *      mapping keeps a running maximum, not a history. Snapshotting per set rather than only
     *      for the tip keeps repeated removals correct, since each removal exposes a new tip whose
     *      own predecessor values must still be known.
     */
    uint64[][] internal _priorEffectiveAt;

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    uint256 public configVersion;

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    string public bootstrapPeers;

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    string public directPeers;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the initial owner.
     *
     * @dev Deliberately takes no config. Seeding happens after deployment, which keeps the creation
     *      code independent of the config payload so that revising seed data before launch does not
     *      change the deployed address.
     *
     * @param _initialOwner Address of the contract owner.
     */
    constructor(
        address _initialOwner
    ) {
        _transferOwnership(_initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function validatorSetCount() public view returns (uint256) {
        return _validatorSets.length;
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function validatorSetAt(
        uint256 index
    ) public view returns (ValidatorSet memory) {
        if (index >= _validatorSets.length) revert InvalidRange();
        return _validatorSets[index];
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function validatorSets() external view returns (ValidatorSet[] memory) {
        uint256 count = _validatorSets.length;
        ValidatorSet[] memory sets = new ValidatorSet[](count);
        for (uint256 i; i < count; ++i) {
            sets[i] = _validatorSets[i];
        }
        return sets;
    }

    /*//////////////////////////////////////////////////////////////
                             TOML RENDERING
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function configToml() external view returns (string memory) {
        return string(_rangeToml(0, _validatorSets.length, true));
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function validatorSetsToml(uint256 start, uint256 end) external view returns (string memory) {
        return string(_rangeToml(start, end, false));
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function peersToml() public view returns (string memory) {
        return string(_peersToml());
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function appendValidatorSet(
        uint64 effectiveAt,
        uint32[] calldata shardIds,
        bytes32[] calldata validatorPublicKeys
    ) external onlyOwner {
        uint256 index = _validatorSets.length;
        _validatorSets.push();
        _priorEffectiveAt.push();
        _writeValidatorSet(index, effectiveAt, shardIds, validatorPublicKeys);

        emit AppendValidatorSet(index, effectiveAt, shardIds, validatorPublicKeys, ++configVersion);
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function amendLatestValidatorSet(
        uint64 effectiveAt,
        uint32[] calldata shardIds,
        bytes32[] calldata validatorPublicKeys
    ) external onlyOwner {
        uint256 count = _validatorSets.length;
        if (count == 0) revert NoValidatorSets();

        uint256 index = count - 1;
        _writeValidatorSet(index, effectiveAt, shardIds, validatorPublicKeys);

        emit AmendValidatorSet(index, effectiveAt, shardIds, validatorPublicKeys, ++configVersion);
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function removeLatestValidatorSet() external onlyOwner {
        uint256 count = _validatorSets.length;
        if (count == 0) revert NoValidatorSets();

        uint256 index = count - 1;
        _rollBackEffectiveAt(index);

        // pop() is specified to clear the nested dynamic arrays, but clearing them explicitly means
        // that getting this wrong is not possible: a later push() inheriting stale contents would
        // silently resurrect a removed validator.
        ValidatorSet storage validatorSet = _validatorSets[index];
        delete validatorSet.shardIds;
        delete validatorSet.validatorPublicKeys;
        _validatorSets.pop();

        delete _priorEffectiveAt[index];
        _priorEffectiveAt.pop();

        emit RemoveValidatorSet(index, ++configVersion);
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function setBootstrapPeers(
        string calldata peers
    ) external onlyOwner {
        _validatePeerString(peers);

        emit SetBootstrapPeers(bootstrapPeers, peers, ++configVersion);

        bootstrapPeers = peers;
    }

    /**
     * @inheritdoc ISnapchainConfigRegistry
     */
    function setDirectPeers(
        string calldata peers
    ) external onlyOwner {
        _validatePeerString(peers);

        emit SetDirectPeers(directPeers, peers, ++configVersion);

        directPeers = peers;
    }

    /*//////////////////////////////////////////////////////////////
                           RENDERING HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Render validator sets `[start, end)`, optionally followed by the `[gossip]` table.
     *
     *      Assembly is two-level and deliberately so. Each entry is built on its own, and the
     *      entries are joined into the result exactly once. A flat one-concat-per-line loop would
     *      be quadratic in output bytes, and the EVM's quadratic memory term compounds it: at a
     *      hundred entries that difference is the getter working versus exceeding every public
     *      eth_call gas cap.
     */
    function _rangeToml(uint256 start, uint256 end, bool includePeers) internal view returns (bytes memory) {
        if (start > end || end > _validatorSets.length) revert InvalidRange();

        uint256 count = end - start;
        bytes[] memory parts = new bytes[](includePeers ? count + 1 : count);
        for (uint256 i; i < count; ++i) {
            parts[i] = _validatorSetToml(_validatorSets[start + i]);
        }
        if (includePeers) parts[count] = _peersToml();

        return _join(parts);
    }

    /**
     * @dev Render one validator set as a `[[consensus.validator_sets]]` block.
     *
     *      The block carries its own trailing blank line rather than sitting between separators.
     *      That is what makes paginated ranges concatenate into exactly the unpaginated document.
     */
    function _validatorSetToml(
        ValidatorSet storage validatorSet
    ) internal view returns (bytes memory) {
        uint32[] storage shardIds = validatorSet.shardIds;
        bytes32[] storage publicKeys = validatorSet.validatorPublicKeys;

        // Bounded at MAX_SHARD_IDS, so the quadratic term here is irrelevant.
        bytes memory shardList = bytes(Strings.toString(shardIds[0]));
        for (uint256 i = 1; i < shardIds.length; ++i) {
            shardList = bytes.concat(shardList, ", ", bytes(Strings.toString(shardIds[i])));
        }

        uint256 keyCount = publicKeys.length;
        bytes memory keyLines = new bytes(keyCount * _KEY_LINE_LENGTH);
        for (uint256 i; i < keyCount; ++i) {
            _writeKeyLine(keyLines, i * _KEY_LINE_LENGTH, publicKeys[i]);
        }

        return bytes.concat(
            "[[consensus.validator_sets]]\n",
            "effective_at = ",
            bytes(Strings.toString(validatorSet.effectiveAt)),
            "\n",
            "shard_ids = [",
            shardList,
            "]\n",
            "validator_public_keys = [\n",
            keyLines,
            "]\n\n"
        );
    }

    /**
     * @dev Render the `[gossip]` table. Both values are safe to interpolate unescaped because the
     *      setters reject every byte that could close the string literal.
     */
    function _peersToml() internal view returns (bytes memory) {
        return bytes.concat(
            "[gossip]\n",
            "bootstrap_peers = \"",
            bytes(bootstrapPeers),
            "\"\n",
            "direct_peers = \"",
            bytes(directPeers),
            "\"\n"
        );
    }

    /**
     * @dev Concatenate `parts` into one buffer with a single allocation and one copy per part.
     */
    function _join(
        bytes[] memory parts
    ) internal pure returns (bytes memory) {
        uint256 total;
        for (uint256 i; i < parts.length; ++i) {
            total += parts[i].length;
        }

        bytes memory out = new bytes(total);
        uint256 offset;
        for (uint256 i; i < parts.length; ++i) {
            bytes memory part = parts[i];
            uint256 length = part.length;
            assembly ("memory-safe") {
                mcopy(add(add(out, 0x20), offset), add(part, 0x20), length)
            }
            offset += length;
        }
        return out;
    }

    /**
     * @dev Write one `  "<64 hex chars>",\n` line into `out` at `offset`.
     *
     *      Written straight into the caller's buffer rather than returned as a fresh string, and in
     *      assembly rather than through indexed writes to a `bytes memory`. Both matter: this runs
     *      once per key per call, and the Solidity version -- an allocation, 64 bounds-checked
     *      single-byte writes, then a concat that copies the result again -- costs roughly an order
     *      of magnitude more. That difference is what decides whether the getter fits inside a
     *      public RPC's eth_call gas cap once the history grows.
     */
    function _writeKeyLine(bytes memory out, uint256 offset, bytes32 key) internal pure {
        assembly ("memory-safe") {
            let ptr := add(add(out, 0x20), offset)

            // `  "`
            mstore8(ptr, 0x20)
            mstore8(add(ptr, 1), 0x20)
            mstore8(add(ptr, 2), 0x22)

            // byte(n, symbols) indexes from the most significant byte, so the alphabet is
            // left-aligned in the word and a nibble indexes it directly.
            let symbols := _HEX_SYMBOLS_ALIGNED
            let hexPtr := add(ptr, 3)
            for { let i := 0 } lt(i, 32) { i := add(i, 1) } {
                let word := byte(i, key)
                let pos := add(hexPtr, mul(i, 2))
                mstore8(pos, byte(shr(4, word), symbols))
                mstore8(add(pos, 1), byte(and(word, 0x0F), symbols))
            }

            // `",\n`
            mstore8(add(ptr, 67), 0x22)
            mstore8(add(ptr, 68), 0x2C)
            mstore8(add(ptr, 69), 0x0A)
        }
    }

    /*//////////////////////////////////////////////////////////////
                           MUTATION HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Validate and write a validator set at `index`, which must already exist.
     *
     *      Append and amend share this one path, so an amend cannot drift from an append, and
     *      amending entry N is bounded by the entries before it for free. Members are assigned
     *      individually rather than assigning a whole struct, which sidesteps the compiler's
     *      unimplemented memory-to-storage copy for structs with nested dynamic arrays and
     *      correctly resizes the existing arrays on an amend.
     */
    function _writeValidatorSet(
        uint256 index,
        uint64 effectiveAt,
        uint32[] calldata shardIds,
        bytes32[] calldata validatorPublicKeys
    ) internal {
        _validateShardIds(shardIds);
        _validateValidatorPublicKeys(validatorPublicKeys);

        // On an amend this entry already contributes to `_lastEffectiveAt`; undo that first so the
        // incoming value is bounded by the entries preceding it rather than by the value it is
        // replacing. On an append the entry was just pushed and governs no shards, so this is a
        // no-op and the two paths stay identical.
        _rollBackEffectiveAt(index);
        _applyEffectiveAt(index, effectiveAt, shardIds);

        ValidatorSet storage validatorSet = _validatorSets[index];
        validatorSet.effectiveAt = effectiveAt;
        validatorSet.shardIds = shardIds;
        validatorSet.validatorPublicKeys = validatorPublicKeys;
    }

    /**
     * @dev Bound `effectiveAt` against the most recent preceding set **for each shard this set
     *      governs**, then record it at `index`.
     *
     *      The comparison is per shard because `effectiveAt` is a per-shard Snapchain block height.
     *      Shard 0 and the message shards advance on independent counters, so two sets governing
     *      disjoint shards carry heights on different clocks and cannot be meaningfully ordered
     *      against each other. Bounding a set against its immediate array predecessor regardless of
     *      shard would make a legitimate rollout unrepresentable: with shard 0 last set at height
     *      50_000_000 and shard 1 currently at 30_000_000, no correct shard-1 set could be appended,
     *      and the only accepted values would activate it at the wrong height.
     *
     *      Sets governing disjoint shards are therefore unconstrained relative to one another.
     *      Within a shard the bound is `>=` rather than `>`, since a rollout may legitimately land
     *      at a height already used by a sibling set.
     *
     *      Snapchain's own scan is order-independent (see the ordering section of
     *      docs/snapchain-config-registry.md), so this is a guard against operator error rather than
     *      a consumer requirement. It is worth keeping: a too-low height for a shard backdates that
     *      set over already-committed blocks, changing which keys verify historical commits and
     *      breaking sync from genesis.
     *
     *      Reverting partway leaves the writes above it to be rolled back with the transaction, so
     *      checking and recording in one pass is safe. Duplicate shard ids are already rejected, so
     *      no shard is visited twice.
     */
    function _applyEffectiveAt(uint256 index, uint64 effectiveAt, uint32[] calldata shardIds) internal {
        uint256 shardCount = shardIds.length;
        uint64[] memory priors = new uint64[](shardCount);

        for (uint256 i; i < shardCount; ++i) {
            uint32 shardId = shardIds[i];
            uint64 prior = _lastEffectiveAt[shardId];
            if (effectiveAt < prior) revert InvalidEffectiveAt();

            priors[i] = prior;
            _lastEffectiveAt[shardId] = effectiveAt;
        }

        _priorEffectiveAt[index] = priors;
    }

    /**
     * @dev Undo the contribution the set at `index` made to `_lastEffectiveAt`, restoring the value
     *      each of its shards held immediately before it was written.
     *
     *      Exact rather than approximate: the snapshot is taken per set, so this restores the bound
     *      to what the preceding sets imply even after the tip has been amended repeatedly or
     *      several sets have been removed in turn.
     *
     *      A set that governs no shards — the empty entry `appendValidatorSet` pushes before writing
     *      — contributes nothing, so this is a no-op there.
     */
    function _rollBackEffectiveAt(
        uint256 index
    ) internal {
        uint32[] storage shardIds = _validatorSets[index].shardIds;
        uint64[] storage priors = _priorEffectiveAt[index];

        uint256 shardCount = shardIds.length;
        for (uint256 i; i < shardCount; ++i) {
            _lastEffectiveAt[shardIds[i]] = priors[i];
        }
    }

    /**
     * @dev Require a non-empty, bounded, duplicate-free list of shard ids.
     */
    function _validateShardIds(
        uint32[] calldata shardIds
    ) internal pure {
        uint256 length = shardIds.length;
        if (length == 0 || length > MAX_SHARD_IDS) revert InvalidShardIds();

        for (uint256 i; i < length; ++i) {
            for (uint256 j = i + 1; j < length; ++j) {
                if (shardIds[i] == shardIds[j]) revert InvalidShardIds();
            }
        }
    }

    /**
     * @dev Require a non-empty, bounded, duplicate-free list of non-zero public keys.
     *
     *      A duplicate key would silently double that operator's voting weight, so this is a safety
     *      property rather than hygiene. Ed25519 point validity is deliberately not checked: there
     *      is no cheap onchain test, and an invalid point fails loudly at node startup.
     */
    function _validateValidatorPublicKeys(
        bytes32[] calldata validatorPublicKeys
    ) internal pure {
        uint256 length = validatorPublicKeys.length;
        if (length == 0 || length > MAX_VALIDATOR_PUBLIC_KEYS) revert InvalidValidatorPublicKeys();

        for (uint256 i; i < length; ++i) {
            if (validatorPublicKeys[i] == bytes32(0)) revert InvalidValidatorPublicKeys();
            for (uint256 j = i + 1; j < length; ++j) {
                if (validatorPublicKeys[i] == validatorPublicKeys[j]) revert InvalidValidatorPublicKeys();
            }
        }
    }

    /**
     * @dev Require every byte of a peer string to be in the allowlist. The empty string is valid:
     *      Snapchain defaults both peer lists to empty and a seed node legitimately has none.
     *
     *      Offending input is rejected rather than sanitized. Silently stripping characters would
     *      store a value the owner did not write and hide the mistake at the moment it matters.
     */
    function _validatePeerString(
        string calldata peers
    ) internal pure {
        bytes calldata raw = bytes(peers);
        uint256 length = raw.length;
        if (length > MAX_PEER_STRING_LENGTH) revert InvalidPeerString();

        for (uint256 i; i < length; ++i) {
            uint8 char = uint8(raw[i]);
            if (char > 0x7F) revert InvalidPeerString();
            uint256 allowed = char < 0x40 ? _PEER_CHARS_LO : _PEER_CHARS_HI;
            // Parenthesised for the reader, not the compiler: Solidity binds `&` tighter than
            // `==`, the opposite of C, so this groups correctly either way.
            if (((allowed >> (char & 0x3F)) & 1) == 0) revert InvalidPeerString();
        }
    }
}
