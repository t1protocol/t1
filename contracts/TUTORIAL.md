# 𝚝𝟷 Tutorials

This doc will help you get started with building on 𝚝𝟷. It provides a simple demo project to show how to deploy and use
contracts directly on 𝚝𝟷, moving Ether and tokens betweens the L1 and 𝚝𝟷, and more.

## Why Build on 𝚝𝟷?

𝚝𝟷 offers near-instant settlement between chains, enabling new types of cross-chain applications that were previously
impossible. Some exciting use cases include:

- cross-chain DEX with near-instant settlement
- yield-bearing limit orders on [𝚝DEX](https://t-dex.v006.t1protocol.com/) (our native orderbook DEX)
- intent-based bridges with real-time execution
- secure auction mechanisms with L1 finality within 1-2 blocks

## Essentials

- **L2 RPC URL**: `https://rpc.v006.t1protocol.com`
- **Chain ID**: `299792`
- **[Block Explorer](https://explorer.v006.t1protocol.com/)**
- **Test tokens**: [WETH](https://explorer.v006.t1protocol.com/address/0xC521c60FF61CC615e8233F41B07250fC12cE5c57),
  [USDT](https://explorer.v006.t1protocol.com/address/0xb6E3F86a5CE9ac318F54C9C7Bcd6eff368DF0296)

### Contract ABIs

ABIs will appear in the ./artifacts directory after running `forge build`

### Protocol Contract Addresses

Protocol contract addresses can be found in the highest version of [/deployments/bridge](./deployments/bridge)

### Getting Funds on 𝚝𝟷

The easiest way to get funds onto 𝚝𝟷 is to use the [devnet portal](https://devnet.t1protocol.com)

## Deploying Contracts

We're a fan of [foundry](https://book.getfoundry.sh/) and highly recommend using it to test and deploy your contracts.

We've provided a [DeployExample.s.sol](./script/deploy/DeployExample.s.sol) script as a template for deploying contracts
to 𝚝𝟷. Once you have provided a private key for the env var `L2_DEPLOYER_PRIVATE_KEY`, you can deploy and verify this
contract to 𝚝𝟷 with the following command:

```bash
forge script ./script/deploy/DeployExample.s.sol:DeployExample --broadcast --verify --verifier blockscout --verifier-url $BLOCKSCOUT_API_URL
```

## Interacting with 𝚝𝟷's ERC-7683

Ensure that you have copied over default environment variables:

```bash
cp .env.example .env
```

Set the following private key addresses. For the purpose of this demo, they can be the same, but it's required that the
`TEST_PRIVATE_KEY` has ETH on 𝚝𝟷 in order to pay gas:

- `ALICE_PRIVATE_KEY`: Alice's private key for signing the transaction.
- `TEST_PRIVATE_KEY`: Solver's private key for signing the transaction.

To execute the scripts defined in `7683E2E.s.sol`, follow these steps:

1. Setup Alice's Account

```bash
forge script ./script/test/7683E2E.s.sol:AliceSetupScript --rpc-url $T1_L1_RPC --broadcast
```

2. Solver Fills on L2

```bash
forge script ./script/test/7683E2E.s.sol:SolverFillScript --rpc-url $T1_L2_RPC --broadcast
```

3. Settlement and Relay

```bash
forge script ./script/test/7683E2E.s.sol:SettlementScript --rpc-url $T1_L2_RPC --broadcast
```
