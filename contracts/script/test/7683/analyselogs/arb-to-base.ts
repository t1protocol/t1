import { ethers } from "ethers";
import T1ERC7683 from "../../../../artifacts/src/T1ERC7683.sol/T1ERC7683.json";

// -------------------- Config --------------------
const arbProvider = new ethers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");
const arbErc7683Address  = "0x996f3583bd967bba19694733aa7a7623e6d780eb";

const baseProvider = new ethers.JsonRpcProvider("https://base-rpc.publicnode.com");
const baseErc7683Address  = "0xdbA711a6c1b187479e9a5b33020E5217D0BD5A1f";

const arbFromBlock = 418241010;
const arbLatest    = 418842847;
// const arbLatest = await arbProvider.getBlockNumber();

const baseFromBlock = 40423900;
const baseLatest    = 40499026;
// const baseLatest    = await baseProvider.getBlockNumber();

const step = 10_000;

const iface = new ethers.Interface(T1ERC7683.abi);

// Topics
const openTopic0   = iface.getEvent("Open")!.topicHash;
const filledTopic0 = iface.getEvent("Filled")!.topicHash;

const norm = (x: string) => x.toLowerCase();

// -------------------- 1) Collect Opens on Arbitrum --------------------
const openedByOrderId = new Map(); // orderId -> { orderId, blockNumber, txHash, logIndex, args? }

for (let start = arbFromBlock; start <= arbLatest; start += step + 1) {
  const end = Math.min(arbLatest, start + step);

  const logs = await arbProvider.getLogs({
    address: arbErc7683Address,
    fromBlock: start,
    toBlock: end,
    topics: [openTopic0],
  });

  for (const log of logs) {
    const orderId = norm(log.topics[1]!); // indexed orderId

    // Dedup by orderId (keep first seen)
    if (!openedByOrderId.has(orderId)) {
      openedByOrderId.set(orderId, {
        orderId,
        blockNumber: log.blockNumber,
        txHash: log.transactionHash,
        logIndex: log.index,
      });
    }
  }
}

console.log(`Searched in Arbitrum blocks from ${arbFromBlock} to ${arbLatest} and found...`);
console.log("Opened unique orderIds on Arbitrum:", openedByOrderId.size);

// -------------------- 2) Collect Fills on Base --------------------
const filledOrderIds = new Set();

for (let start = baseFromBlock; start <= baseLatest; start += step + 1) {
  const end = Math.min(baseLatest, start + step);

  const logs = await baseProvider.getLogs({
    address: baseErc7683Address,
    fromBlock: start,
    toBlock: end,
    topics: [filledTopic0],
  });

  for (const log of logs) {
    const orderId = norm(log.topics[1]!); // indexed orderId
    filledOrderIds.add(orderId);
  }
}

console.log(`Searched in Base blocks from ${baseFromBlock} to ${baseLatest} and found...`);
console.log("Filled unique orderIds on Base:", filledOrderIds.size);

// -------------------- 3) Diff: Opened on Arb but NOT Filled on Base --------------------
const unfilledOpenEvents = [];
for (const [orderId, openEvent] of openedByOrderId.entries()) {
  if (!filledOrderIds.has(orderId)) unfilledOpenEvents.push(openEvent);
}

console.log("Unfilled count:", unfilledOpenEvents.length);
console.log("Unfilled orders:", JSON.stringify(unfilledOpenEvents, null, 2));
