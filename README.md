# Contracts

Implementation of the AccountRegistry and Namespace contracts specified in the [Farcaster protocol](https://github.com/farcasterxyz/protocol). The contracts are built with [Foundry](https://github.com/foundry-rs/foundry), a modular toolkit for developing Ethereum contracts. Please see the [documentation](docs/namespace.md) for more details about the contracts.

## :package: Installing Dependencies

First, ensure that the following are installed globally on your machine:

- [Yarn](https://classic.yarnpkg.com/lang/en/docs/install)
- [Foundry](https://github.com/foundry-rs/foundry)

Then, from the project root, run `yarn install` to install NPM dependencies. Once this is done you can run `forge build` and `forge test` to verify that everything is set up correctly.

## :nail_care: Style Guide

- `yarn lint` uses [Prettier Solidity](https://github.com/prettier-solidity/prettier-plugin-solidity) to find and auto-correct common problems.
- `yarn lint:check` performs the same checks, but alerts on errors and does not fix them.

Code follows the [Solidity style guide](https://docs.soliditylang.org/en/v0.8.15/style-guide.html) and documentation follows Ethereum [Natspec](https://docs.soliditylang.org/en/develop/natspec-format.html) unless otherwise specified. If you use VS Code, you can lint-on-save by installing the [Solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) and [ESLint](https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint) extensions.

## Deploying

Account Registry Deployment Addresses:

| Network | Address                                                                                                                       |
| ------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Rinkeby | [0x0a632c23d86ed99daf4450a2c7cfc426b23781d9](https://rinkeby.etherscan.io/address/0x0a632c23d86ed99daf4450a2c7cfc426b23781d9) |

A new instance of the contract can be deploying by using forge to execute the deployment script. To do this, create a `.env` file with the following secrets:

- `RINKEBY_RPC_URL`- get this from alchemy or infura
- `RINKEBY_PRIVATE_KEY` - [export](https://metamask.zendesk.com/hc/en-us/articles/360015289632-How-to-export-an-account-s-private-key) this from your rinkeby metamask wallet
- `ETHERSCAN_KEY` - get this from the [etherscan api](https://etherscan.io/myapikey.)

Next, source the environment variables into your shell:

`source .env`

Use forge to run the deploy script, which can take a few minutes to complete:

`forge script script/AccountRegistry.s.sol:AccountRegistryScript --rpc-url $RINKEBY_RPC_URL --private-key $RINKEBY_PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY -vvvv`

The deploy script will generate .json outputs to track the latest deployments and transactions. Do not commit these changes unless you are modifying one of the published contracts above.

# Troubleshooting

You can learn more about Foundry by reading [the book](https://book.getfoundry.sh/index.html).

### Estimating Gas Usage

Forge ships with a gas reporting tool which provides gas reports for function calls. It can be invoked with `forge test --gas-report`. But these numbers can be misleading because test suites invoke functions in ways that make them terminate very early. Some functions also vary in cost for the same code path because of storage initialization during certain invocations.

The best way to estimate gas usage accurately is to write a special test suite that follows code paths that you expect to see in real-world usage. Running the gas report on just this suite will give you the most accurate estimate.
