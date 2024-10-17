# Farcaster Protocol Runbooks

[![Txtx](https://img.shields.io/badge/Operated%20with-Txtx-gree?labelColor=gray)](https://txtx.sh)

## Available Runbooks

`txtx` Runbooks are the perfect companion to Foundry when creating Solidity smart contracts.
Foundry shines in making the development process a breeze; `txtx` makes deploying and operating on your contracts secure, simple, and reproducible.

The following Runbooks are available for this project.

### Deploy L1
Deploys all L1 contracts. To execute, run:
```console
txtx run deploy-l1 -u --env devnet
```

### Deploy L2
Deploys all L2 contracts. To execute, run: 
```console
txtx run deploy-l2 -u --env devnet
```

### Grant Role
Calls the grantRole function of the StorageRegistry contract. To execute, run: 
```console
txtx run grant-role --env devnet
```

## Getting Started

This repository is using [txtx](https://txtx.sh) for handling its on-chain operations.

`txtx` takes its inspiration from a battle tested devops best practice named `infrastructure as code`, that have transformed cloud architectures. 


### Installation

#### macOS
```console
brew tap txtx/txtx
brew install txtx
```
#### Linux
```console
sudo snap install txtx
```

### List runbooks available in this repository
```console
$ txtx ls
ID                                      Name                                    Description
deploy-l1                               Deploy L1                               Deploys all L1 contracts
deploy-l2                               Deploy L2                               Deploys all L2 contracts
grant-role                              Grant Role                              Calls the grantRole function of the StorageRegistry contract
```

### Scaffold a new runbook

```console
$ txtx new
```

Access tutorials and documentation at [docs.txtx.sh](https://docs.txtx.sh) to understand the syntax and discover the powerful features of txtx. 

Additionally, the [Visual Studio Code extension](https://marketplace.visualstudio.com/items?itemName=txtx.txtx) will make writing runbooks easier.



### Execute an existing runbook
```console
$ txtx run <runbook-id>
```

