# SnapchainConfigRegistry — onchain schema and TOML rendering spec

This document is the normative agreement between `SnapchainConfigRegistry` and its consumers. The
contract renders a TOML fragment; a client fetches that fragment over `eth_call` and merges it into
a Snapchain node's `config.toml` before the node process starts. Because the node parses those bytes
directly, the output format is part of the contract's public API and is specified here to the byte.

## 1. Motivation

Snapchain validators are configured with three values that must agree across every node in the
network:

| Key                                | Type in Snapchain                | Source today                            |
| ---------------------------------- | -------------------------------- | --------------------------------------- |
| `consensus.validator_sets`         | `Vec<ValidatorSetConfig>`        | hand-edited `validators.toml`, per node |
| `gossip.bootstrap_peers`           | comma-separated `String`         | hand-edited, per node                   |
| `gossip.direct_peers`              | comma-separated `String`         | hand-edited, per node                   |

There is no central record of what the set _should_ be, and no way for a third party to audit how it
has changed. This registry makes the validator-set history an onchain, append-only, publicly
readable artifact, and makes the two peer lists owner-settable strings alongside it.

Everything else in a node's config — its identity, its private key, its storage paths — stays local
and is never touched by the registry.

## 2. Data model

```solidity
struct ValidatorSet {
    uint64 effectiveAt;
    uint32[] shardIds;
    bytes32[] validatorPublicKeys;
}
```

This mirrors `ValidatorSetConfig` in `snapchain/src/consensus/consensus.rs`.

### 2.1 `effectiveAt` is a Snapchain block height

Not an EVM block number, not a timestamp. Values in the current mainnet config run from `0`
(genesis) to `39_798_000`. Nothing onchain can validate this number against Snapchain's actual
height — it is operator-supplied and operator-checked.

### 2.2 Public keys are `bytes32`, not `string`

Ed25519 public keys are exactly 32 bytes, so `bytes32` is the natural type. It is also the
load-bearing security decision in this design: a `bytes32` can only ever render through a fixed
16-character hex alphabet, which makes it **structurally impossible** for a validator-set entry to
break out of its TOML string literal. See §5.

The consequence is that the registry cannot store a malformed key that would be caught early. An
invalid Ed25519 point is 32 well-formed bytes as far as the contract is concerned, and there is no
cheap onchain check for point validity. Such a key is caught at node startup, where
`StoredValidatorSet::new` panics rather than continuing with a partial set — loud, and before the
node joins consensus.

### 2.3 Ordering and `effectiveAt` monotonicity

Entries are stored in an append-only array. An entry's `effectiveAt` must be **greater than or equal
to** that of the most recent preceding entry **governing a shard in common**. Entries governing
disjoint shards are unconstrained relative to one another.

The bound is per shard, not over the array as a whole, because `effectiveAt` is a per-shard height
(§2.1). Shard 0 and the message shards advance on independent counters, so heights drawn from two
different shards are values on two different clocks and ordering them against each other is not a
meaningful operation.

Bounding each entry against its immediate array predecessor regardless of shard would make
legitimate rollouts unrepresentable. With shard 0 last set at height 50,000,000 and shard 1 currently
at 30,000,000, no correct shard-1 entry could be appended at all: every value the check accepts is
tens of millions of blocks in that shard's future, so the operator either cannot ship the change or
writes a height that activates the set at the wrong time. That the current mainnet history happens to
ascend under a whole-array reading is a coincidence of how those ten rollouts landed, not a property
that holds going forward.

`>=` rather than `>` within a shard, since a rollout may legitimately land at a height already used
by a sibling entry.

Snapchain resolves the active set with a linear scan
(`StoredValidatorSets::get_validator_set`, `snapchain/src/consensus/validator.rs`):

```rust
let mut result = &self.sets[0];
for config in &self.sets {
    if config.shard_ids.contains(&self.shard_id)
        && config.effective_at <= height
        && config.effective_at > result.effective_at
    {
        result = config;
    }
}
```

Two properties follow, and both constrain this spec:

- **The scan itself is order-independent** — it takes the maximum `effectiveAt` not exceeding
  `height` among entries matching the shard. Rendering in array order is therefore safe regardless
  of how the array is sorted, and out-of-order entries resolve correctly. The per-shard bound is
  enforced onchain as a guard against operator error, not because the consumer requires it. It earns
  its place even so: a height typed too low for a shard backdates that set over already-committed
  blocks, changing which keys verify historical commits and breaking sync from genesis.
- **Entry 0 is load-bearing.** It seeds the search unconditionally, without checking `shardIds` or
  `effectiveAt`, and an empty array panics on `sets[0]`. Entry 0 must therefore be the genesis
  entry: `effectiveAt == 0` and every shard listed. This is a property of the seeded data, not
  something the contract can enforce, and it is why the registry must never be read while empty.

Because ties are resolved by `>` rather than `>=`, two entries with the same `effectiveAt` that
cover the same shard are ambiguous — the earlier one in array order wins. The contract does not
reject this; operators must not create it.

### 2.4 Peer strings

`bootstrapPeers` and `directPeers` are plain owner-settable strings, not append-only. There is no
value in an audit trail of gossip addresses, and they change for operational reasons unrelated to
consensus membership.

The empty string is valid for both. Snapchain's default is `""` and a seed node legitimately has no
bootstrap peers.

> Note for the consumer: `Config::bootstrap_addrs()` splits on `,` without filtering empties, so an
> empty `bootstrap_peers` yields a single empty address rather than an empty list. That is
> pre-existing Snapchain behaviour, but it means writing `""` over a node's existing peer list is
> not a no-op. The pull client should treat an empty registry value as a value, not as "unset".

### 2.5 One network-wide peer list, where today there are many

The registry holds a single `bootstrapPeers` and a single `directPeers` for the whole network. That
is a deliberate change from how these values are configured today: **every validator currently runs
its own peer lists, each omitting itself.** Across the current Snapchain mainnet and testnet
deployments, no two nodes share a pair, and the read nodes carry a different shape again (bootstrap
peers but no direct peers).

Collapsing that into one list per network is safe, and is part of the point of centralizing:

- A node that finds its own multiaddr in `bootstrap_peers` attempts to dial itself, which libp2p
  discards. Self-inclusion is inert.
- `direct_peers` is only consulted as a membership set for connection-management decisions, so a
  node's own peer id in that set has no effect on who it connects to.

What it does change is that peer-related metrics computed over the configured set now count one
extra element on every node. Whoever wires up the rollout should confirm no alert threshold is
defined against the raw configured count before cutting over.

Seeding therefore means constructing the **union** of the per-node lists, not copying one node's.
The pull client must also apply the registry's peer values only to validators — read nodes keep
their existing configuration path.

## 3. Rendered output

The canonical getter is:

```solidity
function configToml() external view returns (string memory);
```

Its output is exactly `validatorSetsToml(0, validatorSetCount())` concatenated with `peersToml()`.

### 3.1 Grammar

```
configToml     := validatorSetBlock*  peersBlock
validatorSetBlock :=
    "[[consensus.validator_sets]]\n"
    "effective_at = " uint "\n"
    "shard_ids = [" uint (", " uint)* "]\n"
    "validator_public_keys = [\n"
    ("  \"" hex64 "\",\n")*
    "]\n"
    "\n"
peersBlock :=
    "[gossip]\n"
    "bootstrap_peers = \"" peerString "\"\n"
    "direct_peers = \"" peerString "\"\n"
```

Fixed points, each asserted by the contract's test suite:

- **Integers** are plain decimal with no digit separators and no leading zeros: `26386684`, `0`.
  Snapchain's checked-in `validators.toml` writes `26_386_684`; TOML treats the two as identical and
  the contract emits the underscore-free form. This difference is intentional and must not be
  "fixed".
- **Public keys** are exactly 64 lowercase hex characters with no `0x` prefix, zero-padded.
- **The key array uses a trailing comma.** Every element, including the last, is followed by `,\n`.
  TOML permits this, and it removes the is-last branch from the renderer.
- **`shard_ids` has no trailing comma** and no inner bracket spacing: `[0, 1, 2]`, not `[ 0, 1, 2 ]`.
- **Each validator-set block ends with a blank line**, including the last one. The separator belongs
  to the block, not between blocks. This is what makes pagination compose exactly:
  `validatorSetsToml(0, k) + validatorSetsToml(k, n) == validatorSetsToml(0, n)` for every `k`.
- **Two-space indent** on key lines. Nothing else is indented.
- **The document ends in a newline.**
- **No comments.** The operator/key mapping that `validators.toml` carries in comments is not
  onchain. It lives in the deploy script and in this repo's deployment records.

### 3.2 Example

For a registry holding one entry and both peer strings set:

```toml
[[consensus.validator_sets]]
effective_at = 0
shard_ids = [0, 1, 2]
validator_public_keys = [
  "29696eb40eb900a329a8d2542edef15d552c9ba6ded7882276be1e9eca090970",
  "6bc2d8901443de856d2670b0c2ea12b6727132fa830f9030d3a44ac5da9b1a72",
]

[gossip]
bootstrap_peers = "/ip4/10.0.0.148/udp/3382/quic-v1, /ip4/10.0.2.165/udp/3382/quic-v1"
direct_peers = "12D3KooWGmXDC2SfjSG7h7DchyVJHMB4GpA8JYpHf9iwz8L8BFqB"
```

With no entries at all, `configToml()` is just the `[gossip]` block. That document is syntactically
valid but semantically unusable — a node loading it panics on `sets[0]`. The registry is expected to
be seeded before any node reads it.

## 4. Read surface

| Function                                | Purpose                                                              |
| --------------------------------------- | -------------------------------------------------------------------- |
| `configToml()`                          | Canonical getter. What every normal client calls.                    |
| `validatorSetsToml(uint256, uint256)`   | Half-open `[start, end)` range. Escape hatch if the document outgrows an `eth_call` gas cap. |
| `peersToml()`                           | The `[gossip]` block alone.                                          |
| `validatorSetCount()`                   | Array length; pairs with the paginated getter.                       |
| `validatorSetAt(uint256)`               | One entry as a struct, for clients that would rather not parse TOML.  |
| `validatorSets()`                       | The whole array as structs.                                          |
| `configVersion()`                       | Change beacon; see §6.                                               |

Out-of-range indices revert with `InvalidRange` rather than surfacing a `Panic(0x32)`.

## 5. TOML injection

The two peer strings are the only free-form operator input that reaches the rendered document, and
they are interpolated into double-quoted TOML literals. A `"` or a newline in one of them closes the
literal early and lets the remainder of the string be parsed as TOML — including a synthetic
`[[consensus.validator_sets]]` block at `effective_at = 0` naming an attacker's keys.

Mutation is owner-only, so this is not a path from an unprivileged caller to a consensus takeover.
It is a path from a **single mistyped or pasted-wrong owner transaction** to one, which is worth
closing at the contract rather than trusting every future client to escape correctly.

### 5.1 The allowlist

`setBootstrapPeers` and `setDirectPeers` accept only these bytes:

```
a-z  A-Z  0-9  .  -  _  /  :  ,  (space)
```

That covers every multiaddr and base58 PeerId form in use — `/ip4/…/udp/3382/quic-v1`,
`/ip6/::1/tcp/3382`, `/dns4/host.example.com/tcp/3382/p2p/12D3Koo…`, and bare
`12D3KooWGmXDC2SfjSG7h7DchyVJHMB4GpA8JYpHf9iwz8L8BFqB`. Space is allowed because the current
deployer config uses `, ` as a separator and Snapchain trims each element after splitting.

Everything else reverts with `InvalidPeerString`. Notably excluded: `"` `\` `#` `=` `[` `]` `'`
`{` `}`, every control character including `\n` `\r` `\t`, and every byte above `0x7E`.

`#` and `=` are excluded even though they are harmless inside a quoted literal. They cost nothing to
forbid and they mean the value stays inert if some future consumer ever renders it unquoted.

### 5.2 Reject, do not sanitize

A setter that silently strips offending characters stores a value the operator did not write, and
hides the mistake at exactly the moment it matters. Reverting surfaces it in the transaction that
caused it.

### 5.3 What this leaves

With keys as `bytes32` and peers behind the allowlist, no field in the rendered document can contain
a `"`. The invariant asserted as a property test is therefore exact: the number of `"` characters in
`configToml()` is always `2 * totalKeys + 4`.

`MAX_PEER_STRING_LENGTH` is 8192 bytes, which bounds the per-call validation loop and keeps the two
strings from dominating the output size.

## 6. `configVersion`

`uint256 public configVersion`, incremented by exactly one on every mutation, before the
corresponding event is emitted. It starts at `0`, so a client that initialises its own watermark to
`0` correctly sees deploy-time seeding as a change.

This exists so a poller can detect "did anything change" with one cheap `eth_call` instead of
fetching and diffing several kilobytes. The obvious alternative — `configHash()` returning
`keccak256(bytes(configToml()))` — is semantically nicer but costs as much as `configToml()` itself,
which defeats the purpose.

## 7. Validation split

Enforced onchain:

- `shardIds` and `validatorPublicKeys` are non-empty
- no zero public key
- no duplicate public key — a duplicate silently doubles an operator's voting weight, which is a
  safety property rather than hygiene
- no duplicate shard id
- `effectiveAt >= ` that of the most recent preceding entry sharing a shard (§2.3); entries over
  disjoint shards are unconstrained relative to one another
- `shardIds.length <= MAX_SHARD_IDS` (16) and `validatorPublicKeys.length <=
  MAX_VALIDATOR_PUBLIC_KEYS` (128), bounding the O(n²) duplicate scans and, transitively, the
  rendered size
- the peer-string allowlist and length cap

Deliberately left to the operator:

- **Ed25519 point validity** — no cheap onchain check; fails loudly at node startup instead.
- **Shard-id range** — the network's shard count is unknown onchain and grows over time.
- **Quorum safety of the delta between entries** — this is policy, not protocol. A contract-level
  check that rejected, say, replacing more than a third of the set at once would be a false positive
  exactly when an emergency rotation needs to happen.
- **`effectiveAt` being in the future** — Snapchain's current height is unknowable onchain.

## 8. Mutability of the tip

History is append-only. The **latest** entry may be amended in place or removed entirely; earlier
entries cannot be touched.

Allowing removal, not just amendment, is deliberate. If an entry should not exist at all, amending
can only overwrite it with _something_, and that something must still satisfy the per-shard
`effectiveAt` bound. There is no value that means "no entry". Since the owner can already
rewrite the tip's entire contents, refusing to let them delete it is false rigor: append-only here is
an auditability discipline over history, not a security boundary over the tip.

Both operations are recorded as events, so the audit trail survives even when the state does not.

## 9. Gas and capacity

### 9.1 What actually limits an `eth_call`

There is no protocol-level gas limit on `eth_call` — it is off-chain execution, so every limit is a
node or provider policy knob:

- **Node software.** The geth-family default (`--rpc.gascap` in geth, reth and erigon; `--rpc-gas-cap`
  in besu) is **50,000,000**. Setting it to `0` means unlimited.
- **Providers** layer their own on top, usually lower, and frequently expressed as a wall-clock
  timeout or a compute-unit budget rather than a gas number. These are not reliably documented and
  differ per plan.
- **Response size** is a separate ceiling. A 200 KB TOML document becomes roughly 400 KB of
  hex-encoded JSON; some providers cap response bodies well below where gas becomes the problem.

The test suite holds the renderer to **10M**, which is a deliberately conservative floor rather than
a documented universal minimum. Whoever operates a validator should measure against the endpoint
`l1_rpc_url` actually points at, since that is the only limit that matters in practice.

### 9.2 Measured curve

Rendering 8 keys per entry across 3 shards, with both peer strings populated:

| entries | rendered size | `configToml()` | worst 50-entry page |
| ------: | ------------: | -------------: | ------------------: |
|      10 |          7 KB |           436k |                   — |
|      50 |         32 KB |          2.20M |               2.21M |
|     100 |         64 KB |          4.59M |               2.29M |
|     150 |         96 KB |          6.97M |               2.40M |
|     200 |        128 KB |         10.34M |               2.55M |
|     250 |        161 KB |         13.90M |               2.73M |
|     300 |        193 KB |         18.06M |               2.94M |

Mainnet holds **10 entries today** — the first row. The full render is superlinear, roughly `O(n^1.4)`:
per-entry cost climbs from ~44k at 10 entries to ~60k at 300, because the intermediate buffers and
the EVM's quadratic memory term both grow with the document. It crosses the conservative 10M floor
at **≈195 entries** and would reach a 50M cap somewhere past 500.

The list grows by one entry per shard per validator rotation — 3 per rotation at the current shard
count. The history to date is 3 rotations in about 15 months, so 195 entries is on the order of
**decades** at the current rate, and adding a shard changes that arithmetic more than adding
validators does.

### 9.3 Mitigations

1. **Per-entry assembly and a single join.** Each entry is built on its own and the entries are
   concatenated into the result exactly once, sized up front. A flat one-concat-per-line loop is
   quadratic in output bytes and the memory term compounds it.
2. **Key lines written directly into the output buffer.** The straightforward version — allocate a
   string per key, fill it with bounds-checked single-byte writes, then concat it in — measured 3.5×
   more expensive across the whole document.
3. **Pagination.** `validatorSetsToml(start, end)` with `validatorSetCount()`. The right-hand column
   above is the point: a fixed 50-entry page stays near 3M regardless of how long the history gets,
   because page cost tracks page size and not total size. Pages concatenate into byte-identical
   output, so a client that outgrows the single call can switch without any change to what it
   parses.

`configVersion()` remains the cheap poll; `configToml()` is only called when it moves.

## 10. Deployment shape

Two registries, both on Ethereum L1 mainnet, distinguished by address and by CREATE2 salt: one for
Snapchain mainnet, one for Snapchain testnet. Testnet validators already point at the same L1 RPC
endpoint as mainnet ones, so a separate chain would mean provisioning a second RPC secret for no
isolation benefit — the isolation that matters is between config sets, not between chains.

The constructor takes only `_initialOwner` and no config. Seeding happens in the deploy script's
setup phase, which keeps the creation code — and therefore any CREATE2 vanity address — independent
of the config payload, so revising seed data before launch does not force re-mining a salt.

## 11. Consumers

- `fc config pull` (Snapchain repo) — fetches `configToml()`, parses it, and deep-merges the three
  keys into a node's `config.toml`, replacing rather than appending. A parse-merge is required
  rather than a text append because `[[consensus.validator_sets]]` is append-safe but `[gossip]` is
  not: both of Snapchain's container entrypoints already emit a `[gossip]` table, and TOML rejects a
  second one.
- The container startup script, which runs the pull only in validator mode, honours an override flag
  for mounted configs, and falls back to a cached last-known-good document if the RPC call fails.
  Refusing to boot a validator because an RPC blipped is worse than running one rotation stale.
