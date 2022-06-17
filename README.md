# Contracts

Implementation of the AccountRegistry and Namespace contracts specified in the [Farcaster protocol](https://github.com/farcasterxyz/protocol).The contracts are built with [Foundry](https://github.com/foundry-rs/foundry), a modular toolkit for developing Ethereum contracts.

## :package: Installing Dependencies

The only dependency you'll need is foundry which can be installed with `curl -L https://foundry.paradigm.xyz | bash`. If you prefer installing from source, there are instructions in the [repository](https://github.com/foundry-rs/foundry).

Once this is done you can run `forge build` and `forge test` to verify. You can learn more about Foundry by reading [the book](https://book.getfoundry.sh/index.html).

## :nail_care: Style Guide

We follow the conventions in the [Solidity style guide](https://docs.soliditylang.org/en/v0.8.15/style-guide.html) unless otherwise specified below. Solidity linting is performed using [solhint](https://github.com/protofire/solhint), and JSON linting is performed with [ESLint](https://eslint.org/).

If you use VS Code, you can lint on save by installing the [Solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) and [ESLint](https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint) extensions.

## Troubleshooting

### Estimating Gas Usage

You can run `forge test --gas-estimate` to calculate the approximate cost of any method. It's important to invoke methods multiple times to get an accurate gas cost because initialization costs can make the first invocation more expensive.
