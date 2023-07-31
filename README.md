# Contracts

This repository contains all the contracts deployed by the [Farcaster protocol](https://github.com/farcasterxyz/protocol). The contracts are:

1. **[Id Registry](./src/IdRegistry.sol)** - issues farcaster identities (fids) to new users.
2. **[Storage Registry](./src/StorageRegistry.sol)** - allocates storage to fids and collects rent.
3. **[Key Registry](./src/KeyRegistry.sol)** - allows users with an fid to register key pairs for signing messages.
4. **[Bundler](./src/Bundler.sol)** - allows calling registry and storage in a single transaction.
5. **[Fname Resolver](./src/FnameResolver.sol)** - validates Farcaster ENS names which were issued off-chain.

Read the [docs](docs/docs.md) for more details on how the contracts work.

## Contributing

Please see the [contributing guidelines](CONTRIBUTING.md).

## Location

### v3 Contracts

The v3 contracts have not yet been deployed.

### v2 Contracts

The [v2 contracts](https://github.com/farcasterxyz/contracts/releases/tag/v2.0.0) can be found at the following addresses on L1 Goerli:

| Network        | Address                                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| IdRegistry     | [0xda107a1caf36d198b12c16c7b6a1d1c795978c42](https://goerli.etherscan.io/address/0xda107a1caf36d198b12c16c7b6a1d1c795978c42) |
| NameRegistry   | [0xe3be01d99baa8db9905b33a3ca391238234b79d1](https://goerli.etherscan.io/address/0xe3be01d99baa8db9905b33a3ca391238234b79d1) |
| BundleRegistry | [0xdb647193df79ce69b5d34549aae98d519223f682](https://goerli.etherscan.io/address/0xdb647193df79ce69b5d34549aae98d519223f682) |
