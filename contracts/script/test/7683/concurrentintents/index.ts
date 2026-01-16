import "dotenv/config";
import crypto from "node:crypto";
import {
  createPublicClient,
  createWalletClient,
  webSocket,
  parseGwei,
  encodeAbiParameters,
  encodeFunctionData,
  padHex,
  type Abi,
  type Hex,
  type Address, type Chain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrum, base } from "viem/chains";

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

function asHexPrivateKey(v: string): Hex {
  return (v.startsWith("0x") ? v : `0x${v}`) as Hex;
}

function asAddress(v: string): Address {
  if (!v.startsWith("0x") || v.length !== 42) throw new Error(`Invalid address: ${v}`);
  return v as Address;
}

function addressToBytes32(a: Address): Hex {
  return padHex(a, { size: 32 });
}

const TX_COUNT = Number(process.env.TX_COUNT ?? "100");
const TX_CONCURRENCY = Number(process.env.TX_CONCURRENCY ?? "25");
const PRIORITY_FEE_GWEI = process.env.PRIORITY_FEE_GWEI ?? "0.05";

const AMOUNT_IN = BigInt(process.env.AMOUNT_IN ?? "100");
const MIN_OUT_BPS = BigInt(process.env.MIN_OUT_BPS ?? "9000"); // 9000 = 90%
const FILL_DEADLINE_SECONDS = BigInt(process.env.FILL_DEADLINE_SECONDS ?? "300");

const ERC20_ABI = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const satisfies Abi;

// Minimal ABI for T1ERC7683.open(OnchainCrossChainOrder)
const T1ERC7683_ABI = [
  {
    type: "function",
    name: "open",
    stateMutability: "payable",
    inputs: [
      {
        name: "_order",
        type: "tuple",
        components: [
          { name: "fillDeadline", type: "uint32" },
          { name: "orderDataType", type: "bytes32" },
          { name: "orderData", type: "bytes" },
        ],
      },
    ],
    outputs: [],
  },
] as const satisfies Abi;

// bytes32 orderDataType = keccak256("OrderData(...same as OrderEncoder...)")
// We hardcode the value by computing it at runtime from the exact type string.
import { keccak256, toHex } from "viem";
const ORDER_DATA_TYPE_STRING =
  "OrderData(" +
  "bytes32 sender," +
  "bytes32 recipient," +
  "bytes32 inputToken," +
  "bytes32 outputToken," +
  "uint256 amountIn," +
  "uint256 minAmountOut," +
  "uint256 senderNonce," +
  "uint32 originDomain," +
  "uint32 destinationDomain," +
  "bytes32 destinationSettler," +
  "uint32 fillDeadline," +
  "bool closedAuction," +
  "bytes data)";

const ORDER_DATA_TYPEHASH = keccak256(toHex(ORDER_DATA_TYPE_STRING)) as Hex;

type ChainCfg = {
  name: string;
  chain: Chain;
  wsUrl: string;
  privateKey: Hex;

  t1Erc7683: Address;

  // origin-side token address
  inputToken: Address;

  // destination-side token address (encoded into orderData)
  outputToken: Address;

  destinationSettler: Address;

  originDomain: number; // uint32
  destinationDomain: number; // uint32
};

function randomUint256(): bigint {
  return BigInt(`0x${crypto.randomBytes(32).toString("hex")}`);
}

async function approveIfNeeded(cfg: ChainCfg, walletClient: any, publicClient: any) {
  // For speed/simplicity, we just send approve(max). Many tokens allow repeated approve(max).
  const maxUint256 = (1n << 256n) - 1n;

  const data = encodeFunctionData({
    abi: ERC20_ABI,
    functionName: "approve",
    args: [cfg.t1Erc7683, maxUint256],
  });

  const suggested = await publicClient.estimateFeesPerGas();
  const maxPriorityFeePerGas = parseGwei(PRIORITY_FEE_GWEI);
  const maxFeePerGas =
    suggested.maxFeePerGas && suggested.maxFeePerGas > maxPriorityFeePerGas
      ? suggested.maxFeePerGas
      : maxPriorityFeePerGas;

  const request = await publicClient.prepareTransactionRequest({
    account: privateKeyToAccount(cfg.privateKey),
    to: cfg.inputToken,
    data,
    value: 0n,
    maxFeePerGas,
    maxPriorityFeePerGas,
  });

  const signed = await walletClient.signTransaction(request);
  const hash = await publicClient.sendRawTransaction({ serializedTransaction: signed });

  console.log(`[${cfg.name}] approve tx: ${hash}`);
  await publicClient.waitForTransactionReceipt({ hash });
}

async function runChain(cfg: ChainCfg) {
  const account = privateKeyToAccount(cfg.privateKey);
  const owner = account.address;

  const transport = webSocket(cfg.wsUrl, {
    reconnect: { attempts: Infinity, delay: 500 },
    keepAlive: { interval: 15_000 },
  });

  const publicClient = createPublicClient({ chain: cfg.chain, transport });
  const walletClient = createWalletClient({ chain: cfg.chain, transport, account });

  const [baseNonce, now] = await Promise.all([
    publicClient.getTransactionCount({ address: owner, blockTag: "pending" }),
    publicClient.getBlock(), // includes timestamp
  ]);

  const suggested = await publicClient.estimateFeesPerGas();
  const maxPriorityFeePerGas = parseGwei(PRIORITY_FEE_GWEI);
  const maxFeePerGas =
    suggested.maxFeePerGas && suggested.maxFeePerGas > maxPriorityFeePerGas
      ? suggested.maxFeePerGas
      : maxPriorityFeePerGas;

  console.log(
    `[${cfg.name}] from=${owner} startNonce=${baseNonce} maxFeePerGas=${maxFeePerGas} maxPriorityFeePerGas=${maxPriorityFeePerGas}`,
  );

  // One approval before the burst (consumes 1 nonce).
  await approveIfNeeded(cfg, walletClient, publicClient);

  // Re-fetch nonce after approve, to be safe.
  const startNonce = await publicClient.getTransactionCount({ address: owner, blockTag: "pending" });

  const minAmountOut = (AMOUNT_IN * MIN_OUT_BPS) / 10_000n;
  const baseTimestamp = BigInt(now.timestamp);

  // Pre-sign all open() txs for speed.
  const signedTxs: Hex[] = [];
  for (let i = 0; i < TX_COUNT; i++) {
    const senderNonce = randomUint256();
    const fillDeadline = Number(baseTimestamp + FILL_DEADLINE_SECONDS); // fits uint32 for normal timestamps

    // OrderData (solidity) as ABI tuple encoding (equivalent to abi.encode(orderData))
    const encodedOrderData = encodeAbiParameters(
      [
        {
          type: "tuple",
          name: "orderData",
          components: [
            { name: "sender", type: "bytes32" },
            { name: "recipient", type: "bytes32" },
            { name: "inputToken", type: "bytes32" },
            { name: "outputToken", type: "bytes32" },
            { name: "amountIn", type: "uint256" },
            { name: "minAmountOut", type: "uint256" },
            { name: "senderNonce", type: "uint256" },
            { name: "originDomain", type: "uint32" },
            { name: "destinationDomain", type: "uint32" },
            { name: "destinationSettler", type: "bytes32" },
            { name: "fillDeadline", type: "uint32" },
            { name: "closedAuction", type: "bool" },
            { name: "data", type: "bytes" },
          ],
        },
      ],
      [
        {
          sender: addressToBytes32(owner),
          recipient: addressToBytes32(owner),
          inputToken: addressToBytes32(cfg.inputToken),
          outputToken: addressToBytes32(cfg.outputToken),
          amountIn: AMOUNT_IN,
          minAmountOut,
          senderNonce,
          originDomain: cfg.originDomain,
          destinationDomain: cfg.destinationDomain,
          destinationSettler: addressToBytes32(cfg.destinationSettler),
          fillDeadline,
          closedAuction: true,
          data: "0x",
        },
      ],
    );

    const callData = encodeFunctionData({
      abi: T1ERC7683_ABI,
      functionName: "open",
      args: [
        {
          fillDeadline,
          orderDataType: ORDER_DATA_TYPEHASH,
          orderData: encodedOrderData,
        },
      ],
    });

    const nonce = startNonce + i;

    const request = await publicClient.prepareTransactionRequest({
      account,
      to: cfg.t1Erc7683,
      data: callData,
      value: 0n,
      nonce,
      maxFeePerGas,
      maxPriorityFeePerGas,
    });

    const signed = await walletClient.signTransaction(request);
    signedTxs.push(signed);
  }

  // Broadcast burst
  let sent = 0;
  const hashes: Hex[] = new Array(TX_COUNT);

  async function worker(workerId: number) {
    for (;;) {
      const idx = sent++;
      if (idx >= signedTxs.length) return;

      const raw = signedTxs[idx]!;
      const hash = await publicClient.sendRawTransaction({ serializedTransaction: raw });
      hashes[idx] = hash;

      console.log(`[${cfg.name}] worker=${workerId} open() ${idx + 1}/${TX_COUNT} hash=${hash}`);
    }
  }

  const workers = Array.from({ length: Math.min(TX_CONCURRENCY, TX_COUNT) }, (_, i) => worker(i));
  const t0 = Date.now();
  await Promise.all(workers);
  const t1 = Date.now();

  console.log(`[${cfg.name}] broadcasted ${TX_COUNT} open() tx in ${t1 - t0}ms`);

  // Optional: wait + show block spread
  const receipts = await Promise.all(hashes.map((h) => publicClient.waitForTransactionReceipt({ hash: h })));
  const blocks = receipts.map((r) => r.blockNumber);
  const minBlock = blocks.reduce((a, b) => (a < b ? a : b));
  const maxBlock = blocks.reduce((a, b) => (a > b ? a : b));
  console.log(`[${cfg.name}] inclusion spread: minBlock=${minBlock} maxBlock=${maxBlock} span=${maxBlock - minBlock}`);

  return { hashes, receipts };
}

async function main() {
  const baseT1 = asAddress(requireEnv("BASE_T1_ERC7683_CONTRACT_ADDRESS"));
  const arbT1 = asAddress(requireEnv("ARBITRUM_T1_ERC7683_CONTRACT_ADDRESS"));

  const baseCfg: ChainCfg = {
    name: "Base (Base→Arb intents)",
    chain: base,
    wsUrl: requireEnv("BASE_WS"),
    privateKey: asHexPrivateKey(requireEnv("BASE_SIGNER_PRIVATE_KEY")),
    t1Erc7683: baseT1,
    inputToken: asAddress(requireEnv("BASE_INPUT_TOKEN")),
    outputToken: asAddress(requireEnv("ARB_INPUT_TOKEN")), // output token lives on destination
    destinationSettler: asAddress(process.env.ARB_DESTINATION_SETTLER ?? arbT1),
    originDomain: base.id,
    destinationDomain: arbitrum.id,
  };

  const arbCfg: ChainCfg = {
    name: "Arbitrum (Arb→Base intents)",
    chain: arbitrum,
    wsUrl: requireEnv("ARBITRUM_WS"),
    privateKey: asHexPrivateKey(requireEnv("ARBITRUM_SIGNER_PRIVATE_KEY")),
    t1Erc7683: arbT1,
    inputToken: asAddress(requireEnv("ARB_INPUT_TOKEN")),
    outputToken: asAddress(requireEnv("BASE_INPUT_TOKEN")), // output token lives on destination
    destinationSettler: asAddress(process.env.BASE_DESTINATION_SETTLER ?? baseT1),
    originDomain: arbitrum.id,
    destinationDomain: base.id,
  };

  // Run both bursts in parallel so they line up in time as tightly as possible.
  await Promise.all([runChain(baseCfg), runChain(arbCfg)]);
  console.log("Done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
