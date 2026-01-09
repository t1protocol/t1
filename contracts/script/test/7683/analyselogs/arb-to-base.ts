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

type OpenEntry = {
  orderId: string;
  blockNumber: number;
  blockTimestamp: number;
  txHash: string;
  logIndex: number;
};

type FilledEntry = {
  orderId: string;
  blockNumber: number;
  blockTimestamp: number;
  txHash: string;
  logIndex: number;
};

// -------------------- 1) Collect Opens on Arbitrum --------------------
const openedByOrderId = new Map<string, OpenEntry>(); // orderId -> OpenEntry

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
      const blk = await arbProvider.getBlock(log.blockNumber);
      const blockTimestamp = Number(blk?.timestamp ?? 0);

      openedByOrderId.set(orderId, {
        orderId,
        blockNumber: log.blockNumber,
        blockTimestamp,
        txHash: log.transactionHash,
        logIndex: log.index,
      });
    }
  }
}

console.log(`Searched in Arbitrum blocks from ${arbFromBlock} to ${arbLatest} and found...`);
console.log("Opened unique orderIds on Arbitrum:", openedByOrderId.size);

// -------------------- 2) Collect Fills on Base --------------------
const filledByOrderId = new Map<string, FilledEntry>(); // orderId -> FilledEntry

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

    // Dedup by orderId (keep first seen)
    if (!filledByOrderId.has(orderId)) {
      const blk = await baseProvider.getBlock(log.blockNumber);
      const blockTimestamp = Number(blk?.timestamp ?? 0);

      filledByOrderId.set(orderId, {
        orderId,
        blockNumber: log.blockNumber,
        blockTimestamp,
        txHash: log.transactionHash,
        logIndex: log.index,
      });
    }
  }
}

console.log(`Searched in Base blocks from ${baseFromBlock} to ${baseLatest} and found...`);
console.log("Filled unique orderIds on Base:", filledByOrderId.size);

// -------------------- 3) Diff: Opened on Arb but NOT Filled on Base --------------------
const unfilledOpenEvents: OpenEntry[] = [];
for (const [orderId, openEvent] of openedByOrderId.entries()) {
  if (!filledByOrderId.has(orderId)) unfilledOpenEvents.push(openEvent);
}

console.log("Unfilled count:", unfilledOpenEvents.length);
console.log("Unfilled orders:", JSON.stringify(unfilledOpenEvents, null, 2));

// -------------------- 4) Fill time stats for matched orders --------------------
const fillDurationsSec: number[] = [];
const matchedCount = (() => {
  let cnt = 0;
  for (const [orderId, openEvent] of openedByOrderId.entries()) {
    const filled = filledByOrderId.get(orderId);
    if (filled) {
      const delta = filled.blockTimestamp - openEvent.blockTimestamp;
      // Only include non-negative durations
      if (Number.isFinite(delta) && delta >= 0) {
        fillDurationsSec.push(delta);
        cnt++;
      }
    }
  }
  return cnt;
})();

if (matchedCount === 0) {
  console.log("No matched open->fill pairs within the specified ranges. Skipping stats.");
} else {
  let fastest = Infinity;
  let slowest = -Infinity;
  let sum = 0;

  for (const d of fillDurationsSec) {
    if (d < fastest) fastest = d;
    if (d > slowest) slowest = d;
    sum += d;
  }
  const avg = sum / fillDurationsSec.length;

  console.log("Matched open->fill pairs:", matchedCount);
  console.log("Fastest fill time (s):", fastest);
  console.log("Slowest fill time (s):", slowest);
  console.log("Average fill time (s):", avg);
}
