# Farcaster Contracts Documentation

Documentation that covers the high-level functionality of each contract in the system.

## Table of Contents

1. [ID Registry](#1-id-registry)
2. [Storage Contract](#2-storage-contract)

## 1. ID Registry

The ID Registry contract issues Farcaster IDs (fids) for the Farcaster network.

An `fid` is a uint256 that represents a unique user of the network. Fids begin at 0 and increment by one for every new account. There is an infinite supply of fids since they can go as high as ~10^77. IDs begin in the seedable state, where they can only be registered by a pre-determined address. The owner can disable trusted registration which then allows anyone to register an fid.

Each address can only own a single fid at a time, but they can otherwise be freely transferred between addresses. The address that currently owns an fid is known as the `custody address`. The contract implements a recovery system that protects users if they lose access to this address.

### State Machine

An fid can exist in these states:

- `seedable` - the fid has never been issued, and can be registered by the trusted caller
- `registerable` - the fid has never been issued, and can be registered by anyone
- `registered` - the fid has been issued to an address
- `escrow` - a recovery request has been submitted and is pending escrow
- `recoverable` - a recovery request has completed escrow and is pending completion.

```mermaid
    stateDiagram-v2
        direction LR
        seedable --> registerable: disable trusted register
        seedable --> registered: trusted register
        registerable --> registered: register
        registered --> registered: transfer
        registered --> escrow: request recovery
        escrow --> recoverable: end(escrow)
        recoverable --> registered: transfer, cancel <br>  or complete recovery
        escrow --> registered: transfer <br> cancel recovery
```

The fid state transitions when users take specific actions:

- `register` - register a new fid from any address
- `trusted register` - register a new fid from the trusted caller
- `disable trusted register` - allow registration from any sender
- `transfer` - move an fid to a new custody address
- `request recovery` - request a recovery of the fid
- `cancel recovery` - cancel a recovery that is in progress
- `complete recovery` - complete a recovery that has passed the escrow period

The fid state can automatically transition when certain periods of time pass:

- `end(escrow)` - 3 days from the `request recovery` action


### Recovery System

The contract implement a recovery system that protects the owner against the loss of the `custody address`.

1. The `custody address` can nominate a `recovery address` that is authorized to move a fid on its behalf. This can be changed or removed at any time.

2. The `recovery address` can send a recovery request which moves the fid into the `escrow` state. After the escrow period, the fid becomes `recoverable`, and the `recovery address` can complete the transfer.

3. During `escrow`, the `custody address` can cancel the recovery, which protects against malicious recovery addresses.

4. The `recovery address` is removed, and any active requests are cancelled if the `custody address` changes due to a transfer or other action.

# 2. Storage Contract

TBD
