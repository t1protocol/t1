[![Reth](https://github.com/t1protocol/t1/actions/workflows/reth.yml/badge.svg)](https://github.com/t1protocol/t1/actions/workflows/reth.yml)
[![Contracts](https://github.com/t1protocol/t1/actions/workflows/contracts.yml/badge.svg)](https://github.com/t1protocol/t1/actions/workflows/contracts.yml)

[![Solidity][solidity-badge]][solidity]
[![Rust][rust-badge]][rust]
[![Foundry][foundry-badge]][foundry]
[![License: MIT][license-badge]][license]

[solidity]: https://soliditylang.org/
[solidity-badge]: https://img.shields.io/badge/Solidity-%5E0.8-blueviolet?logo=solidity
[rust]: https://www.rust-lang.org/
[rust-badge]: https://img.shields.io/badge/Rust-stable-orange?logo=rust
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

# 🛠️ 𝚝𝟷 — Real-time proofs to unify Ethereum

𝚝𝟷 is a rollup that introduces real-time proofs to unify Ethereum and the rollup ecosystem.

## 📂 Directory Structure

-This monorepo encompasses essential infrastructure components of the 𝚝𝟷 protocol, including Solidity contracts, rollup node in Rust, and comprehensive end-to-end tests.

- 🧑‍💻 **[contracts](./contracts/README.md)**: Solidity contracts (rollup & pre-deployed contracts)
- 🦀 **[reth](./reth/README.md)**: Rust-based 𝚝𝟷 extension for reth
- 🧪 **[e2e](./e2e/README.md)**: End-to-end testing suite for protocol validation

## 🚧 Quick Start

### 🧰 Dependencies

- [Bun](https://bun.sh/) (recommended package manager)
- [Foundry](https://getfoundry.sh/) (our favorite smart contract toolkit)
- [Docker](https://docs.docker.com/get-docker/) (containerization)

### 📥 Clone & Setup

```bash
git clone https://github.com/t1protocol/t1.git
cd t1
bun install
```

## 💬 Contributing

We ❤️ open-source developers! Here's how you can help:

1. Fork the repository.
2. Create your branch (`git checkout -b feat/amazing-feature`).
3. Commit using our conventional commit guidelines (`bun commit` helps you format).
4. Open a Pull Request 🎉

📖 See [contributing guidelines](CONTRIBUTING.md) for details.

## 👾 Issues

If you find a bug or have a feature request, please open an [issue](https://github.com/t1protocol/t1/issues).

## 🌍 Community

- 🌐 [Website](https://t1protocol.com/)
- 🐦 [Twitter](https://twitter.com/t1protocol)
- 📚 [Documentation](https://docs.t1protocol.com/)
- 💬 [Discord](https://discord.gg/C6kDaJS5)

## License

𝚝𝟷 Monorepo is licensed under the [MIT LICENSE](./LICENSE).
