[![Reth](https://github.com/t1protocol/t1/actions/workflows/reth.yml/badge.svg?branch=develop)](https://github.com/t1protocol/t1/actions/workflows/reth.yml)
[![Contracts](https://github.com/t1protocol/t1/actions/workflows/contracts.yml/badge.svg?branch=develop)](https://github.com/t1protocol/t1/actions/workflows/contracts.yml)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Solidity](https://img.shields.io/badge/Solidity-%5E0.8-blueviolet?logo=solidity.svg)
![Rust](https://img.shields.io/badge/Rust-stable-orange?logo=rust)

# 🛠️ 𝚝𝟷 — Real-time proofs to unify Ethereum

**𝚝𝟷** is pioneering intent-based bridges with RTP (Real Time Proofs) and programmability, enabling secure, flexible, and developer-friendly interactions between blockchain networks.

## 📂 Directory Structure

 This monorepo encompasses essential infrastructure components of the 𝚝𝟷 protocol. It contains the L1 and L2 contracts, the rollup node, and some e2e tests.

- 🧑‍💻 **[contracts](./contracts/README.md)**: Solidity contracts (L1/L2 bridges, rollup & pre-deployed contracts)
- 🦀 **[reth](./reth/README.md)**: Rust-based t1 extension for reth
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

t1 Monorepo is licensed under the [MIT LICENSE](./LICENSE).
