# Contracts

This repository contains all the contracts deployed by the [Farcaster protocol](https://github.com/farcasterxyz/protocol). The contracts are:

1. **[Id Registry](./src/IdRegistry.sol)** - tracks ownership of Farcaster identities (fids).
2. **[Storage Registry](./src/StorageRegistry.sol)** - allocates storage to fids and collects rent.
3. **[Key Registry](./src/KeyRegistry.sol)** - tracks associations between fids and key pairs for signing messages.
4. **[Id Gateway](./src/IdGateway.sol)** - issues Farcaster identities (fids) to new users.
5. **[Key Gateway](./src/KeyGateway.sol)** - adds new associations between fids and keys.
6. **[Bundler](./src/Bundler.sol)** - allows calling gateways and storage in a single transaction.
7. **[Signed Key Request Validator](./src/validators/SignedKeyRequestValidator.sol)** - validates key registry metadata.
8. **[Recovery Proxy](./src/RecoveryProxy.sol)** - proxy for recovery service operators to initiate fid recovery.
9. **[Fname Resolver](./src/FnameResolver.sol)** - validates Farcaster ENS names which were issued offchain.
10. **[Tier Registry](./src/TierRegistry.sol)** - processes Farcaster Pro subscription payments.

Read the [docs](docs/docs.md) for more details on how the contracts work.

## Deployments

The [v3.1 contracts](https://github.com/farcasterxyz/contracts/releases/tag/v3.1.0) are deployed across both OP Mainnet and Ethereum Mainnet.

### OP Mainnet

| Contract                  | Address                                                                                                                          |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| IdRegistry                | [0x00000000fc6c5f01fc30151999387bb99a9f489b](https://optimistic.etherscan.io/address/0x00000000fc6c5f01fc30151999387bb99a9f489b) |
| StorageRegistry           | [0x00000000fcce7f938e7ae6d3c335bd6a1a7c593d](https://optimistic.etherscan.io/address/0x00000000fcce7f938e7ae6d3c335bd6a1a7c593d) |
| KeyRegistry               | [0x00000000fc1237824fb747abde0ff18990e59b7e](https://optimistic.etherscan.io/address/0x00000000fc1237824fb747abde0ff18990e59b7e) |
| IdGateway                 | [0x00000000fc25870c6ed6b6c7e41fb078b7656f69](https://optimistic.etherscan.io/address/0x00000000fc25870c6ed6b6c7e41fb078b7656f69) |
| KeyGateway                | [0x00000000fc56947c7e7183f8ca4b62398caadf0b](https://optimistic.etherscan.io/address/0x00000000fc56947c7e7183f8ca4b62398caadf0b) |
| Bundler                   | [0x00000000fc04c910a0b5fea33b03e0447ad0b0aa](https://optimistic.etherscan.io/address/0x00000000fc04c910a0b5fea33b03e0447ad0b0aa) |
| SignedKeyRequestValidator | [0x00000000fc700472606ed4fa22623acf62c60553](https://optimistic.etherscan.io/address/0x00000000fc700472606ed4fa22623acf62c60553) |
| RecoveryProxy             | [0x00000000fcb080a4d6c39a9354da9eb9bc104cd7](https://optimistic.etherscan.io/address/0x00000000fcb080a4d6c39a9354da9eb9bc104cd7) |

### Base Mainnet

| Contract     | Address                                                                                                               |
| ------------ | --------------------------------------------------------------------------------------------------------------------- |
| TierRegistry | [0x00000000fc84484d585c3cf48d213424dfde43fd](https://basescan.org/address/0x00000000fc84484d585c3cf48d213424dfde43fd) |

### ETH Mainnet

| Contract      | Address          |
| ------------- | ---------------- |
| FnameResolver | Not yet deployed |

## Audits

The [v3.2 contracts](https://github.com/farcasterxyz/contracts/releases/tag/v3.2.0) contracts were reviewed by [0xMacro](https://0xmacro.com/).

The [v3.1 contracts](https://github.com/farcasterxyz/contracts/releases/tag/v3.1.0) contracts were reviewed by [0xMacro](https://0xmacro.com/) and [Cyfrin](https://www.cyfrin.io/).

- [0xMacro Report A-3](https://0xmacro.com/library/audits/farcaster-3.html)
- [Cyfrin Report](https://github.com/farcasterxyz/contracts/blob/fe24a79e8901e8f2479474b16e32f43b66455a1d/docs/audits/2023-11-05-cyfrin-farcaster-v1.0.pdf)

The [v3.0 contracts](https://github.com/farcasterxyz/contracts/releases/tag/v3.0.0) contracts were reviewed by [0xMacro](https://0xmacro.com/):

- [0xMacro Report A-1](https://0xmacro.com/library/audits/farcaster-1.html)
- [0xMacro Report A-2](https://0xmacro.com/library/audits/farcaster-2.html)

## Contributing

Please see the [contributing guidelines](CONTRIBUTING.md).
