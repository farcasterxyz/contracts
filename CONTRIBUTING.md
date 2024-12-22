# Contributing

1. [How to Contribute](#1-how-to-contribute)
2. [Setting up your development environment](#2-setting-up-your-development-environment)
   1. [Installing Dependencies](#21-installing-dependencies)
   2. [Signing Commits](#22-signing-commits)
   3. [Style Guide](#23-style-guide)
   4. [Deploying Contracts](#24-deploying-contracts)
   5. [Troubleshooting Issues](#25-troubleshooting-issues)
3. [Proposing Changes](#3-proposing-changes)
   1. [Writing Tests](#31-writing-tests)
   2. [Writing Docs](#32-writing-docs)
   3. [Auditing Changes](#33-auditing-changes)
   4. [Creating the PR](#34-creating-the-pr)

## 1. How to Contribute

Thanks for your interest in improving the Farcaster Contracts!

No contribution is too small and we welcome to your help. There's always something to work on, no matter how
experienced you are. If you're looking for ideas, start with the
[good first issue](https://github.com/farcasterxyz/contracts/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
or [help wanted](https://github.com/farcasterxyz/contracts/issues?q=is%3Aopen+is%3Aissue+label%3A%22help+wanted%22)
sections in the issues. You can help make Farcaster better by:

- Opening issues or adding details to existing issues
- Fixing bugs in the code
- Making tests or the ci builds faster
- Improving the documentation
- Keeping dependencies up-to-date
- Proposing and implementing new features

Before you get down to coding, take a minute to consider this:

- If your proposal modifies the [farcaster protocol](https://github.com/farcasterxyz/protocol/), open an issue there
  first.
- If your proposal is a non-trivial change, consider opening an issue first to get buy-in.
- If your issue is a small bugfix or improvement, you can simply make the changes and open the PR.

## 2. Setting up your development environment

### 2.1. Installing Dependencies

Install the following packages globally before you get started:

- [Foundry](https://github.com/foundry-rs/foundry) - smart contract toolchain
- [Slither](https://github.com/crytic/slither#how-to-install) - smart contract static analysis tool
- [Rust/Cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html) - for git pre-commit hooks

Once they are installed globally, run `cargo build`, `forge build`, `forge test` and `slither .` to verify that they
are working. Expect the slither command to print several warnings which are false positives or non-issues.

### 2.2. Signing Commits

All commits must be signed with a GPG key, which is a second factor that proves that your commits came from a device
in your control. It protects against the case where your GitHub account gets compromised. To get started:

1. [Generate new GPG Keys](https://help.github.com/en/github/authenticating-to-github/generating-a-new-gpg-key). We
   recommend using [GPG Suite](https://gpgtools.org/) on OSX.
2. Use `gpg-agent` to remember your password locally

```bash
vi ~/.gnupg/gpg-agent.conf

default-cache-ttl 100000000
max-cache-ttl 100000000
```

3. Upload your GPG Keys to your Github Account
4. Configure Git to [use your keys when signing](https://help.github.com/en/github/authenticating-to-github/telling-git-about-your-signing-key).
5. Configure Git to always sign commits by running `git config --global commit.gpgsign true`
6. Commit all changes with your usual git commands and you should see a `Verified` badge near your commits

### 2.3 Style Guide

- `yarn format` uses [forge fmt](https://github.com/foundry-rs/foundry/tree/master/crates/forge) to find and
  auto-correct formatting issues.
- `yarn format:check` performs the same checks, but alerts on errors and does not fix them.

Code follows the [Solidity style guide](https://docs.soliditylang.org/en/v0.8.18/style-guide.html) and documentation
follows Ethereum [Natspec](https://docs.soliditylang.org/en/develop/natspec-format.html) unless otherwise specified. If
you use VS Code, you can lint-on-save by installing the [Solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity)
and [ESLint](https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint) extensions.

### 2.4 Deploying Contracts

#### Locally (Using Anvil)

Anvil can be used to run a local instance of a blockchain which is useful for rapid testing and prototyping.

1. Run `anvil` in a shell to start the local blockchain.
2. Copy one of the private keys that anvil outputs to pass in as an arg in the next step.
3. Run `forge script script/IdRegistry.s.sol:IdRegistryScript --private-key <private_key> --broadcast --verify --fork-url http://127.0.0.1:8545`
   to deploy the contract

#### To Goerli (Using A Node Provider)

A node provider like Alchemy, Infura or Coinbase can be used to deploy the contract to the Goerli network. First,
create a `.env` file with the following secrets:

- `GOERLI_RPC_URL`- get this from your node provider (alchemy/infura)
- `GOERLI_PRIVATE_KEY` - [export](https://metamask.zendesk.com/hc/en-us/articles/360015289632-How-to-export-an-account-s-private-key)
  this from a non-critical metamask wallet that has some goerli eth
- `ETHERSCAN_KEY` - get this from the [etherscan api](https://etherscan.io/myapikey.)

1. Load the environment variables into your shell with `source .env`

2. Run `forge script script/IdRegistry.s.sol:IdRegistryScript --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY -vvvv`

This can take several seconds and generates .json outputs with deployment details. Do not commit these changes unless
you are making a new public deployment. Passing in the Etherscan params to verify the contract makes your code publicly
available on the contract and allows calling the contract through the UI.

### 2.5 Troubleshooting Issues

#### Solc dyld error on Apple M1

If you see a solc dyld error like the one below and you are on an M1, follow the steps here:
https://github.com/foundry-rs/foundry/issues/2712

```bash
Solc Error: dyld[35225]: Library not loaded: '/opt/homebrew/opt/z3/lib/libz3.dylib'
  Referenced from: '/Users/<yourusername>/.svm/0.8.18/solc-0.8.18'
  Reason: tried: '/opt/homebrew/opt/z3/lib/libz3.dylib' (no such file), '/usr/local/lib/libz3.dylib' (no such file), '/usr/lib/libz3.dylib' (no such file)
```

#### Etherscan verification fails

There's an intermittent issue with Etherscan where verification of the contract fails during deployment. Redeploying
the contract later seems to resolve this.

#### Estimating Gas Changes

Forge's gas reporting tool can be inaccurate when run across our entire test suite. Gas estimates can be lower than
expected because tests cover failure cases that terminate early, or higher than expected because the first test run
always causes storage initialization. A more robust way is to write a special suite of tests that mimic real-world
usage of contracts and estimate gas on those calls only. Our gas estimation suite can be invoked with
`forge test --match-contract GasUsage --gas-report`.

## 3. Proposing Changes

When proposing a change, make sure that you've followed all of these steps before you ask for a review.

### 3.1. Writing Tests

All changes that involve features or bugfixes should have supporting Foundry tests. The tests should:

- Live in the `test/` folder
- Fuzz all possible states including user inputs and time warping
- Cover all code paths and states that were added
- Be written as unit tests, and with supporting feature tests if necessary

### 3.2 Writing Docs

All changes should have supporting documentation that makes reviewing and understand the code easy. You should:

- Update high-level changes in the [contract docs](docs/docs.md).
- Write or update Natspec comments for any relevant functions, variables, constants, events and params.
- Add comments explaining the 'why' when code is not obvious.
- Add a `Safety: ..` comment explaining every use of `unsafe`.
- Add a comment explaining every usage of assembly or fancy math.
- Add a comment explaining every gas optimization along with how much gas it saves.

### 3.3 Auditing Changes

You should walk through the following steps locally before pushing a PR for review:

- Check gas usage by running `forge test -vvv --match-contract Gas`
- Check the coverage with `forge coverage`
- Look for issues with [slither](https://github.com/crytic/slither) by running `slither .`
- Walk through the [solcurity checklist](https://github.com/transmissions11/solcurity)

If your changes increase gas usage, reduce coverage, introduce new slither issues or violate any solcurity rules
you must document the rationale clearly in the PR and in the code if appropriate.

### 3.4. Creating the PR

All submissions must be opened as a Pull Request with a full CI run completed. Assign PR's to [@v / varunsrin](https://github.com/varunsrin)
for review. When creating your PR:

- The PR titles _must_ follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary) spec
- Commit titles _should_ follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary) spec

As an example, a good PR title would look like this:

```
fix(IdRegistry): idCounter should be incremented by 1 before transferring the id
```

While a good commit message might look like this:

```
fix(IdRegistry): idCounter should be incremented by 1 before transferring the id

idCounter was being incremented after the transfer id call which increases gas utilization
in some conditions
```
