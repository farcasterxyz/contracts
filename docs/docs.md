# Farcaster Contracts

```mermaid

graph TD

    subgraph Username
    FR(Fname Registry) --> FS(Fname Server)
    end

    subgraph Identity
    BN(Bundler) --> IR(Id Registry) & SR(Storage Registry) & KR(Key Registry)
    KR --> IR
    end
```

## Table of Contents

1. [Id Registry](#1-id-registry)
2. [Storage Registry](#2-storage)
3. [Key Registry](#3-key-registry)
4. [Bundler](#4-bundler)
5. [Fname Resolver](#5-fname-resolver)

## 1. Id Registry

IdRegistry lets any Ethereum address claim a unique Farcaster ID or `fid`. Fids are unique integers that map 1:1 to an Ethereum address known as the `custody address`. An address can own one fid at a time and transfer it to another address. The custody address may nominate a `recovery address` that can transfer the fid to a new custody address. The custody address can always change or remove the recovery address.

### Invariants

1. An address can only own one fid at a given time.
2. Multiple addresses cannot own the same fid at the same time.
3. If fid n was registered, then all fids from 1...n must also be registered.

### Assumptions

1. owner is not malicious

### Migration

When deployed, the IdRegistry starts in the Seedable state, where only the trusted caller can register fids. Identities from previous versions of the contracts can be registered to their addresses by the owner. Once complete, the owner can move it to the Registrable state, where anyone can register fids. This state change cannot be reversed.

### Administration

The owner can pause and unpause registrations though transfers and recoveries are unaffected.

### State Machine

An fid can exist in three states:

- `seedable` - the fid has never been issued and can be registered by the trusted caller
- `registerable` - the fid has never been issued and can be registered by anyone
- `registered` - the fid has been issued to an address

```mermaid
    stateDiagram-v2
        direction LR
        seedable --> registerable: disable trusted only
        seedable --> registered: trusted register
        registerable --> registered: register
        registered --> registered: transfer, recover
```

The fid state transitions when users take specific actions:

- `register` - register a new fid from any address
- `trusted register` - register a new fid from the trusted caller
- `disable trusted only` - allow registration from any sender
- `transfer` - move an fid to a new custody address
- `recover` - recover (move) an fid to a new custody address

### Upgradeability

The IdRegistry contract may need to be upgraded in case a bug is discovered or the logic needs to be changed. In such cases:

1. A new IdRegistry contract is deployed in a state where only an admin can register fids.
2. The current IdRegistry contract is paused.
3. The new IdRegistry is seeded with all the registered fids in the old contract.
4. The KeyRegistry is updated to point to the new IdRegistry.
5. A new Bundler contract is deployed, pointing to the correct contracts.
6. The new IdRegistry is moved to the registrable state where anyone can register an fid.

# 2. Storage Registry

The StorageRegistry contract lets anyone rent units of storage space on Farcaster Hubs for a given fid. Payment must be made in Ethereum to acquire storage for a year. Acquiring storage emits an event that is read off-chain by the Farcaster Hubs, which allocate space to the user. The contract will deprecate itself one year after deployment, and we expect to launch a new contract with updated logic.

### Pricing

The rental price of a storage unit is fixed in USD but must be paid in ETH. A chainlink price oracle is used to determine the exchange rate. Prices are updated periodically, though checks are in place to avoid updates if prices are stale, out of bounds or if the sequencer was recently restarted.

A price refresh occurs when a transaction is made after the cache period has passed, which fetches the latest rate from the oracle. All transactions in that block can still pay the old price, and the refreshed price is applied to transactions in future blocks. A manual override is also present which can be used to fix the price and override the oracle.

### Invariants

1. rentedUnits never exceed maxUnits.
2. Estimated price equals actual price within a block, i.e. `price(x) == _price(x)`.
3. price is calculated with fixedEthUsdPrice instead of ethUsdPrice if > 0.
4. ethUsdPrice is updated from Chainlink no more often than priceFeedCacheDuration, if fixedEthUsdPrice is not set.

### Assumptions

1. Rented units are never released since we expect to renew the contract after a year, and this avoids expensive calculations.
2. Chainlink oracle always returns a valid price for ETH-USD. (or it must be manually overridden).
3. role admin, admin, treasurer and operator are not malicious

### Migration

The StorageRegistry contract does not contain any special states for migration. Once deployed, the operator can use the credit functions to award storage
units to fids if necessary.

### Administration

An `operator` address can credit storage to fids without the payment of rent. This is used for the initial migration to assign storage to existing users, so that their messages aren't auto-expired from Hubs.

A `treasurer` address can move funds from the contract to a pre-defined `vault` address, but cannot change this destination. Only the `admin` may change the vault address to a new destination.

An `admin` address can modify many parameters including the total supply of storage units, the price of rent, the duration for which exchange prices are valid and the deprecation timestamp.

### Upgradeability

The StorageRegistry contract may need to be upgraded in case a bug is discovered or the logic needs to be changed. In such cases:

1. A new storage contract is deployed and is paused so that storage cannot be rented.
2. Hubs are upgraded so that they respect storage events from both contracts.
3. The older storage contract is deprecated, so that no storage can be rented.
4. A new Bundler contract is deployed, pointing to the correct contracts.
5. The new storage contract is unpaused.

# 3. Key Registry

The Key Registry contract lets addresses with an fid add or remove public keys. Keys added onchain are tracked by Hubs and can be used to sign Farcaster messages. The same key can be added by different fids and can exist in different states. Keys contain a scheme that indicates how they should be interpreted and used. During registration, metadata can also be emitted to provide additional context about the key.

### Schemes

The only scheme today is SCHEME_1 that indicates that a key is an EdDSA key and should be allowed to sign messages on behalf of this fid on Farcaster Hubs.

### Invariants

1. A key can only move to the added state if it was previously in the null state.
2. A key can only move to the removed state if it was previously in the added state.
3. A key can only move to the null state if it was previously in the added state, the contract hasn't been migrated, and the action was performed by the owner.
4. Event invariants are specified in comments above each event.

### Assumptions

1. The IdRegistry contract is functional.
2. owner is not malicious.

### Migration

The KeyRegistry is deployed in the trusted state where keys may not be registered by anyone except the owner. The owner will populate the KeyRegistry with existing state by using bulk operations. Once complete, the owner will call `migrationKeys()` to set a migration timestamp and emit an event. Hubs watch for the `Migrated` event and 24 hours after it is emitted, they cut over to this contract as the source of truth.

### State Machine

A key can exist in four states for each possible fid:

- `unmigrated_null` - the key has never been registered for the given fid and migration has not completed.
- `migrated_null` - the key has never been registered for the given fid and migration has completed.
- `added` - the key has been registered for a given fid.
- `removed` - the key has been registered and then removed for a given fid.

```mermaid
    stateDiagram-v2
        direction LR
        unmigrated_null --> migrated_null: migrateKeys
        unmigrated_null --> added: add, bulkAdd
        migrated_null --> added: add
        added --> removed: remove
        added --> unmigrated_null: bulkReset
```

The key state transitions when fids take specific actions on keys they own:

- `add` - move a key from migrated_null to added for an fid.
- `remove` - move a key from added to removed for an fid.

The key state can also be transitioned by these owner actions that are only possible before the migration:

- `migrateKeys` - move all keys from unmigrated_null to migrated_null.
- `bulkAdd` - move keys from unmigrated_null to added for given fids.
- `bulkReset` - move keys from added to unmigrated_null for given fids.

### Upgradeability

The KeyRegistry contract may need to be upgraded in case a bug is discovered or the logic needs to be changed. In such cases:

1. A new KeyRegistry contract is deployed in a state where only an admin can update keys.
2. The old KeyRegistry contract has its IdRegistry address set to address(0), which prevents changes.
3. The state of all existing keys is copied from the old contract to the new one by an admin.
4. A new Bundler contract is deployed, pointing to the correct contracts.
5. The contract is set to untrusted state where anyone can register keys.

# 4. Bundler

The Bundler contract lets a caller register an fid, rent storage units and register a key in a single transaction to save gas. It is a simple wrapper around contract methods and contains little logic beyond tracking contract addresses, collecting parameters and invoking the appropriate functions.

# 5. Fname Resolver

The Fname Resolver contract validates usernames issued under the \*.fcast.id domain on-chain by implementing [ERC-3668](https://eips.ethereum.org/EIPS/eip-3668) and [ENSIP-10](https://docs.ens.domains/ens-improvement-proposals/ensip-10-wildcard-resolution). The resolver contains the url of the server which issues the usernames and proofs. It maintains a list of valid signers for the server and also validates proofs returned by the server.

### Administration

An `owner` can update the list of valid signers associated with the server.
