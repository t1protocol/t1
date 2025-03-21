# 𝚝𝟷
[![Reth](https://github.com/t1protocol/t1/actions/workflows/reth.yml/badge.svg?branch=develop)](https://github.com/t1protocol/t1/actions/workflows/reth.yml)
[![Contracts](https://github.com/t1protocol/t1/actions/workflows/contracts.yml/badge.svg?branch=develop)](https://github.com/t1protocol/t1/actions/workflows/contracts.yml)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)

Monorepo for 𝚝𝟷

## Directory Structure
Every project in this monorepo has their own setup instructions (e.g., Rust for Reth). Here it goes the list of projects and their READMEs:
- **[contracts](./contracts/README.md)**: Solidity code for t1 L1 bridge and rollup contracts, plus L2 bridge and pre-deployed contracts.
- **[reth](./reth/README.md)**: Rust code for the t1 extension of reth.
- **[e2e](./e2e/README.md)**: End-to-end tests against a specified environment

## Getting Started
Deploying t1 as a protocol involves three primary steps:

1. Setup environment: install prerequisites and clone repo
2. Run node: start the t1 node with optional blockscout explorer
3. Deploy contracts: deploy l1 contracts and initialize l2 predeployed contracts

### Setup Environment

#### Dependencies
- [Bun](https://bun.sh/) is the recommended package manager for this repository. Ensure it's installed before proceeding.
- [Foundry](https://getfoundry.sh/) is our lovely smart contract development toolchain.
- [Docker](https://docs.docker.com/get-docker/) is neccesary to run the different components in our protocol.

#### Clone this repo

```bash
git clone https://github.com/t1protocol/t1.git
cd t1
```

#### Install dependencies

Run the following command at the root level to install all dependencies:

```bash
bun install
```

Husky is used for managing pre-commit hooks. Hooks are installed automatically when you run `bun install`.

## Development Workflow

* Use `bun commit` to ensure your commit messages follow the conventional commit format.
* Check that the program compiles before pushing any changes. The particular command to run will depend on the specific subdirectory that you are working within.

## Contributing

We welcome contributions! To get started:

1. Fork the repo and create a branch for your changes.
2. Ensure your changes pass tests and follow the commit message conventions (`bun commit` helps with this).
3. Open a pull request for review.

### Commit message guidelines

This repo uses [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/) to standardize commit messages. Available commit types include:

* feat: new features
* fix: bug fixes
* docs: documentation updates
* refactor: code refactoring
* test: test updates
* WIP: work in progress (use for intermediate commits)

## License

t1 Monorepo is licensed under the [MIT LICENSE](./LICENSE).
