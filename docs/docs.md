# Farcaster Contracts Documentation

## Table of Contents

1. [Registry](#1-registry)
2. [Storage Contract](#2-storage)
3. [Bundler Contract](#3-bundler)
4. [ENS CCIP Contract](#4-ccip)

## 1. Registry

The Registry contract lets users sign up and claim and identity on the Farcaster network. Users can call the contract to get identifier known as a Farcaster ID or `fid`. This is a unique integer which is mapped to the user's address known as the `custody address`. The Registry starts in the Seedable state where only a `trusted caller` can register new fids. This is used to migrate state safely if the contract ever needs to be redeployed.

A custody address can only own one fid at a time. Fids can be freely transferred between addresses as long as they do not violate this rule. The custody address can optionally nominate a `recovery address` that can authorized to move the fid at anytime. The custody address can change or remove the recovery address at any time.

### Administration

An `owner` address can change the contract state to Registrable, where anyone can register fids. This state change cannot be undone. The owner can also pause and unpause registrations though transfers and recoveries are not affected. 

### State Machine

An fid can exist in three states:

- `seedable` - the fid has never been issued, and can be registered by the trusted caller
- `registerable` - the fid has never been issued, and can be registered by anyone
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


# 2. Storage

The Storage contract lets users with an fid rent storage space on Farcaster Hubs. Users must make a payment in Ethereum to the contract to acquire units of storage for one year. Acquiring storage emits an event which is read off-chian by the Farcaster Hubs, which allocate the appropriate space to the user. There is a maximum number of storage units available for rent defined as tunable parameter. 

The contract is programmed to deprecate itself at a certain date, initialized to 1 year after the deployment. We expect to launch a new contract to handle rent every year with updated logic based on market conditions, though may extend the lifetime of the contract if necessary.

### Pricing

The rent price of a unit of storage is denominated in USD but must be paid in ETH. A chainlink price oracle is used to determine the exchange rate. Prices are updated periodically by calling the price feed, though guardrails are in place to ensure that prices are not updated if they are stale, out of bounds or if the sequencer was recently restarted. 

Price changes occur when a transaction is made after the cache period has passed. The next payment of rent automatically invokes the price refresh. If the price is refreshed in a block, all transactions in that block are still allowed to pay the old price, and the refreshed price is only applied to future blocks, to make payments more predictable. 
 
### Administration

An `operator` address can credit storage to fids without the payment of rent. This is used for the initial migration to assign storage to existing users, so that their messages aren't auto-expired from Hubs.

A `treasurer` address can move funds out of the contract to a pre-defined `vault` address, but cannot change this destination. Only the `admin` may change the address of the vault to a new destination. 

An `admin` address can modify many parameters including the total supply of storage units, the price of rent, the duration for which exchange prices are valid and the deprecation timestamp. 

# 3. Bundler

In Progress

# 4. CCIP

In Progress