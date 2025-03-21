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

For the most up-to-date RPC URL, chain ID, block explorer, and test tokens, please check the **Resources** section of
our [DevNet portal](https://devnet.t1protocol.com/)

### Contract ABIs

ABIs will appear in the ./artifacts directory after running `forge build`

### Protocol Contract Addresses

Protocol contract addresses can be found in the highest version of [/deployments/bridge](./deployments/bridge)

### Getting Funds on 𝚝𝟷

The easiest way to get funds onto t1 is to bridge your own sepolia funds into our layer 2. Everyone can do so navigating
our [devnet portal](https://devnet.t1protocol.com).

## Cross-Chain Arbitrary Message Passing

𝚝𝟷 enables arbitrary message passing between chains, not just token transfers. This powerful primitive allows you to
build truly cross-chain applications where contract calls on one chain can trigger actions on another.

```solidity
// Example: sending a cross-chain message from L1 to t1
bytes memory message = abi.encodeWithSelector(
  MyContract.someFunction.selector,
  param1,
  param2
);

messenger.sendMessage(
  targetContractAddress, // address on destination chain
  0, // value (0 for no ETH transfer)
  message, // encoded function call
  GAS_LIMIT, // gas limit for execution
  destinationChainId // target chain ID
);
```

This enables cross-chain use cases such as:

- intents: verify settlement on destination chain in order to release funds
- lending: borrow against assets on one chain to fund positions on another
- netting: collect orders/positions across multiple chains, and only execute the minimal set of cross-chain settlements

### Cross-Chain Messaging with 𝚝𝟷: Quickstart Guide

This guide walks you through deploying and testing a basic cross-chain messaging contract between sepolia and 𝚝𝟷.

### Prerequisites

- Foundry installed
- Sepolia and 𝚝𝟷 rpc endpoints
- Private keys with funds on both networks
- 𝚝𝟷 messenger contract addresses loaded into `.env`

Step 1: Set up environment

```bash
cp .env.example .env
```

source the environment file:

```bash
source .env
```

Step 2: Deploy the example contracts Run the script to deploy to L1:

```bash
forge script ./script/deploy/DeployCrossChainExample.s.sol:DeployCrossChainExample --sig "deploy_example_to_l1()" --broadcast --verify --verifier etherscan --verifier-url https://api-sepolia.etherscan.io/api --etherscan-api-key $ETHERSCAN_API_KEY
```

Run the script to deploy to 𝚝𝟷:

```bash
forge script ./script/deploy/DeployCrossChainExample.s.sol:DeployCrossChainExample --sig "deploy_example_to_t1()" --broadcast --verify --verifier blockscout --verifier-url https://explorer.v006.t1protocol.com/api
```

Note the deployed contract addresses from the output:

```
export L1_EXAMPLE_ADDR="0x..." # from deployment output
export L2_EXAMPLE_ADDR="0x..." # from deployment output
```

Step 3: Send a cross-chain message Send a message from Sepolia to 𝚝𝟷:

```bash
forge script ./script/test/SendCrossChainMessageExample.s.sol:SendCrossChainMessageExample --sig "send_l1_to_l2_message()" --broadcast
```

Send a message from 𝚝𝟷 to Sepolia:

```bash
forge script ./script/test/SendCrossChainMessageExample.s.sol:SendCrossChainMessageExample --sig "send_l2_to_l1_message()" --broadcast
```

Step 4: Verify message receipt Check the events on your counterchain contract to verify the message was received. This
is often easiest done by navigating to the explorer, but can also be accomplished via a `cast logs` command such as:

```bash
cast logs --rpc-url $T1_L1_RPC --from-block 7949820 "CrossChainRequestReceived(bytes32,address,bytes)"
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
