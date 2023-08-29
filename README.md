# Contracts

This repository contains all the contracts deployed by the [Farcaster protocol](https://github.com/farcasterxyz/protocol). The contracts are:

1. **[Id Registry](./src/IdRegistry.sol)** - issues farcaster identities (fids) to new users.
2. **[Storage Registry](./src/StorageRegistry.sol)** - allocates storage to fids and collects rent.
3. **[Key Registry](./src/KeyRegistry.sol)** - allows users with an fid to register key pairs for signing messages.
4. **[Bundler](./src/Bundler.sol)** - allows calling registry and storage in a single transaction.
5. **[Signed Key Request Validator](./src/validators/SignedKeyRequestValidator.sol)** - validates key registry metadata.
6. **[Recovery Proxy](./src/RecoveryProxy.sol)** - proxy for recovery service operators to initiate fid recovery.
7. **[Fname Resolver](./src/FnameResolver.sol)** - validates Farcaster ENS names which were issued off-chain.

Read the [docs](docs/docs.md) for more details on how the contracts work.

## Contributing

Please see the [contributing guidelines](CONTRIBUTING.md).

## Location

### v3 Contracts

The [v3 contracts](https://github.com/farcasterxyz/contracts/releases/tag/v3.0.0) are deployed on both Optimism mainnet and Ethereum mainnet.

The L2 contracts can be found at the following addresses on Optimism mainnet:

| Contract                  | Address                                                                                                                          |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| IdRegistry                | [0x00000000fcaf86937e41ba038b4fa40baa4b780a](https://optimistic.etherscan.io/address/0x00000000fcaf86937e41ba038b4fa40baa4b780a) |
| StorageRegistry           | [0x00000000fcce7f938e7ae6d3c335bd6a1a7c593d](https://optimistic.etherscan.io/address/0x00000000fcce7f938e7ae6d3c335bd6a1a7c593d) |
| KeyRegistry               | [0x00000000fc9e66f1c6d86d750b4af47ff0cc343d](https://optimistic.etherscan.io/address/0x00000000fc9e66f1c6d86d750b4af47ff0cc343d) |
| Bundler                   | [0x00000000fc94856f3967b047325f88d47bc225d0](https://optimistic.etherscan.io/address/0x00000000fc94856f3967b047325f88d47bc225d0) |
| SignedKeyRequestValidator | [0x00000000fc700472606ed4fa22623acf62c60553](https://optimistic.etherscan.io/address/0x00000000fc700472606ed4fa22623acf62c60553) |
| RecoveryProxy             | [0x00000000fcd5a8e45785c8a4b9a718c9348e4f18](https://optimistic.etherscan.io/address/0x00000000fcd5a8e45785c8a4b9a718c9348e4f18) |

The L1 contract can be found at the following address on Ethereum mainnet:

| Contract                  | Address                                                                                                                          |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| FnameResolver             | Not yet deployed                                                                                                                 |


### v2 Contracts

The [v2 contracts](https://github.com/farcasterxyz/contracts/releases/tag/v2.0.0) can be found at the following addresses on L1 Goerli:

| Contract       | Address                                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| IdRegistry     | [0xda107a1caf36d198b12c16c7b6a1d1c795978c42](https://goerli.etherscan.io/address/0xda107a1caf36d198b12c16c7b6a1d1c795978c42) |
| NameRegistry   | [0xe3be01d99baa8db9905b33a3ca391238234b79d1](https://goerli.etherscan.io/address/0xe3be01d99baa8db9905b33a3ca391238234b79d1) |
| BundleRegistry | [0xdb647193df79ce69b5d34549aae98d519223f682](https://goerli.etherscan.io/address/0xdb647193df79ce69b5d34549aae98d519223f682) |
