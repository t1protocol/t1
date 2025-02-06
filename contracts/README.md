# t1 Contracts [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[gha]: https://github.com/t1protocol/t1/actions
[gha-badge]: https://github.com/t1protocol/t1/actions/workflows/contracts.yml/badge.svg?branch=main
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

This project contains the Solidity code for t1 L1 bridge and rollup contracts, plus L2 bridge and pre-deployed
contracts.

## Directory Structure

<pre>
├── <a href="./script">script</a>: Deployment scripts
├── <a href="./src">src</a>
│   ├── <a href="./src/L1/">L1</a>: Contracts deployed on the L1 (Ethereum)
│   │   ├── <a href="./src/L1/gateways/">gateways</a>: Gateway router and token gateway contracts
│   │   ├── <a href="./src/L1/rollup/">rollup</a>: Rollup contracts for data availability and finalization
│   │   ├── <a href="./src/L1/IL1T1Messenger.sol">IL1T1Messenger.sol</a>: L1 T1 messenger interface
│   │   └── <a href="./src/L1/L1T1Messenger.sol">L1T1Messenger.sol</a>: L1 T1 messenger contract
│   ├── <a href="./src/L2/">L2</a>: Contracts deployed on the L2 (T1)
│   │   ├── <a href="./src/L2/gateways/">gateways</a>: Gateway router and token gateway contracts
│   │   ├── <a href="./src/L2/predeploys/">predeploys</a>: Pre-deployed contracts on L2
│   │   ├── <a href="./src/L2/IL2T1Messenger.sol">IL2T1Messenger.sol</a>: L2 T1 messenger interface
│   │   └── <a href="./src/L2/L2T1Messenger.sol">L2T1Messenger.sol</a>: L2 T1 messenger contract
│   ├── <a href="./src/libraries/">libraries</a>: Shared contract libraries
│   ├── <a href="./src/misc/">misc</a>: Miscellaneous contracts
│   ├── <a href="./src/mocks/">mocks</a>: Mock contracts used in the testing
│   └── <a href="./src/test/">test</a>: Unit tests in solidity
├── <a href="./foundry.toml">foundry.toml</a>: Foundry configuration
├── <a href="./remappings.txt">remappings.txt</a>: Foundry dependency mappings
...
</pre>

## Dependencies

- [Forge](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, format, and deploy smart
  contracts
- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and utilities for testing
- [Husky](https://github.com/typicode/husky): Git hooks made easy
- [Openzeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts): library for secure smart contract development
- [Prettier](https://github.com/prettier/prettier): code formatter for non-Solidity files
- [Solhint](https://github.com/protofire/solhint): linter for Solidity code
- [Solmate](https://github.com/transmissions11/solmate): gas optimized building blocks
- [Uniswap/permit2](https://github.com/Uniswap/permit2/): next generation token approvals mechanism

### Sensible Defaults

This project comes with a set of sensible default configurations for you to use. These defaults can be found in the
following files:

```text
├── .editorconfig
├── .gitignore
├── .prettierignore
├── .prettierrc.yml
├── .solhint.json
├── foundry.toml
└── remappings.txt
```

### GitHub Actions

This project comes with GitHub Actions pre-configured. Your contracts will be linted and tested on every push and pull
request made to the `canary` branch.

You can edit the CI script in [contracts.yml](../.github/workflows/contracts.yml).

## Install Foundry

```
curl -L https://foundry.paradigm.xyz | bash
```

## Installing Dependencies

Foundry typically uses git submodules to manage dependencies, but this project uses Node.js packages because
[submodules don't scale](https://twitter.com/PaulRBerg/status/1736695487057531328).

This is how to install dependencies:

1. Install the dependency using your preferred package manager, e.g. `bun install dependency-name`
   - Use this syntax to install from GitHub: `bun install github:username/repo-name`
2. Add a remapping for the dependency in [remappings.txt](./remappings.txt), e.g.
   `dependency-name=node_modules/dependency-name`

## Writing Tests

To write a new test contract, you start by importing `Test` from `forge-std`, and then you inherit it in your test
contract. Forge Std comes with a pre-instantiated [cheatcodes](https://book.getfoundry.sh/cheatcodes/) environment
accessible via the `vm` property. If you would like to view the logs in the terminal output, you can add the `-vvv` flag
and use [console.log](https://book.getfoundry.sh/faq?highlight=console.log#how-do-i-use-consolelog).

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ bun run build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ bun clean
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ bun format
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ bun run lint
```

### Test & Coverage

Run the tests:

```sh
$ bun run test
```

Generate test coverage and output result to the terminal:

```sh
$ bun test:coverage
```

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
$ bun test:coverage:report
```

## License

This project is licensed under MIT.
