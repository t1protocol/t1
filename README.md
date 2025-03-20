# 𝚝𝟷
[![Reth](https://github.com/t1protocol/t1/actions/workflows/reth.yml/badge.svg?branch=develop)](https://github.com/t1protocol/t1/actions/workflows/reth.yml)
[![Contracts](https://github.com/t1protocol/t1/actions/workflows/contracts.yml/badge.svg?branch=develop)](https://github.com/t1protocol/t1/actions/workflows/contracts.yml)
![License MIT](https://img.shields.io/badge/license-MIT-green.svg)

Monorepo for 𝚝𝟷

## Directory Structure

- **[contracts](./contracts/)**: Solidity code for t1 L1 bridge and rollup contracts, plus L2 bridge and pre-deployed contracts.
- **[reth](./reth/)**: Rust code for the t1 extension of reth.
- **[docker-compose](./docker-compose/)**: Docker compose files to spin up the t1 reth node and other services (currently Blockscout)
- **[e2e](./e2e/)**: End-to-end tests against a specified environment

## Getting Started

### Prerequisites

1. Install [Bun](https://bun.sh/):

Bun is the recommended package manager for this repository. ensure it's installed before proceeding:

```bash
curl https://bun.sh/install | bash
```

2. Clone this repo:

```bash
git clone https://github.com/t1protocol/t1_monorepo.git
cd t1_monorepo
```

### Install dependencies

Run the following command at the root level to install all dependencies:

```bash
bun install
```

NB: Some sub-repos may have their own setup instructions (e.g., Rust for Reth). See the README.md within each subdirectory for details.

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

### Install pre-commit hooks

Husky is used for managing pre-commit hooks. Hooks are installed automatically when you run `bun install`.

## License

t1 Monorepo is licensed under the [MIT license](./LICENSE).
