# Contracts

Implementation of the AccountRegistry and Namespace contracts specified in the [Farcaster protocol](https://github.com/farcasterxyz/protocol). The contracts are built with [Foundry](https://github.com/foundry-rs/foundry), a modular toolkit for developing Ethereum contracts.

## :package: Installing Dependencies

First, ensure that the following are installed globally on your machine:

- [Yarn](https://classic.yarnpkg.com/lang/en/docs/install)
- [Foundry](https://github.com/foundry-rs/foundry)

Then, from the project root, run `yarn install` to install NPM dependencies. Once this is done you can run `forge build` and `forge test` to verify that everything is set up correctly.

## :nail_care: Style Guide

- `yarn lint` uses [Prettier Solidity](https://github.com/prettier-solidity/prettier-plugin-solidity) to find and auto-correct common problems.
- `yarn lint:check` performs the same checks, but alerts on errors and does not fix them.

Code follows the [Solidity style guide](https://docs.soliditylang.org/en/v0.8.15/style-guide.html) and documentation follows Ethereum [Natspec](https://docs.soliditylang.org/en/develop/natspec-format.html) unless otherwise specified. If you use VS Code, you can lint-on-save by installing the [Solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) and [ESLint](https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint) extensions.

## Troubleshooting

You can learn more about Foundry by reading [the book](https://book.getfoundry.sh/index.html).

### Estimating Gas Usage

Forge ships with a gas reporting tool which provides gas reports for function calls. It can be invoked with `forge test --gas-report`. But these numbers can be misleading because test suites invoke functions in ways that make them terminate very early. Some functions also vary in cost for the same code path because of storage initialization during certain invocations.

The best way to estimate gas usage accurately is to write a special test suite that follows code paths that you expect to see in real-world usage. Running the gas report on just this suite will give you the most accurate estimate.
