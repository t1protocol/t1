import { ethers, JsonRpcProvider } from "ethers";
import T1ERC7683 from "../../../../../artifacts/src/T1ERC7683.sol/T1ERC7683.json";

const step = 10_000;

const iface = new ethers.Interface(T1ERC7683.abi);

// Topics
const openTopic0   = iface.getEvent("Open")!.topicHash;
const filledTopic0 = iface.getEvent("Filled")!.topicHash;
const svrTopic0    = iface.getEvent("SettlementVerificationRequested")!.topicHash;
const settledTopic0 = iface.getEvent("Settled")!.topicHash;

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

type RepaymentStartEntry = {
  orderId: string;
  blockNumber: number;
  blockTimestamp: number;
  txHash: string;
  logIndex: number;
};

type RepaymentEndEntry = {
  orderId: string;
  blockNumber: number;
  blockTimestamp: number;
  txHash: string;
  logIndex: number;
};

type AnalyzeBlockParams = {
  sourceChainName: string;
  sourceChainFromBlock: number;
  sourceChainLatest: number;
  sourceChainProvider: JsonRpcProvider;
  sourceChainErc7683Address: `0x${string}`;
  destinationChainName: string;
  destinationChainFromBlock: number;
  destinationChainLatest: number;
  destinationChainProvider: JsonRpcProvider;
  destinationChainErc7683Address: `0x${string}`;
};

export const analyzeERC7683Logs = async (params: AnalyzeBlockParams) => {
  // -------------------- 1) Collect Opens on Source Chain --------------------
  const openedByOrderId = new Map<string, OpenEntry>(); // orderId -> OpenEntry

  for (let start = params.sourceChainFromBlock; start <= params.sourceChainLatest; start += step + 1) {
    const end = Math.min(params.sourceChainLatest, start + step);

    const logs = await params.sourceChainProvider.getLogs({
      address: params.sourceChainErc7683Address,
      fromBlock: start,
      toBlock: end,
      topics: [openTopic0],
    });

    for (const log of logs) {
      const orderId = norm(log.topics[1]!); // indexed orderId

      // Dedup by orderId (keep first seen)
      if (!openedByOrderId.has(orderId)) {
        const blk = await params.sourceChainProvider.getBlock(log.blockNumber);
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

  console.log(`Searched in ${params.sourceChainName} blocks from ${params.sourceChainFromBlock} to ${params.sourceChainLatest} and found...`);
  console.log("Opened unique orderIds on ${params.sourceChainName}:", openedByOrderId.size);

// -------------------- 2) Collect Fills on Destination Chain --------------------
  const filledByOrderId = new Map<string, FilledEntry>(); // orderId -> FilledEntry

  for (let start = params.destinationChainFromBlock; start <= params.destinationChainLatest; start += step + 1) {
    const end = Math.min(params.destinationChainLatest, start + step);

    const logs = await params.destinationChainProvider.getLogs({
      address: params.destinationChainErc7683Address,
      fromBlock: start,
      toBlock: end,
      topics: [filledTopic0],
    });

    for (const log of logs) {
      const orderId = norm(log.topics[1]!); // indexed orderId

      // Dedup by orderId (keep first seen)
      if (!filledByOrderId.has(orderId)) {
        const blk = await params.destinationChainProvider.getBlock(log.blockNumber);
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

  console.log(`Searched in ${params.destinationChainName} blocks from ${params.destinationChainFromBlock} to ${params.destinationChainLatest} and found...`);
  console.log(`Filled unique orderIds on ${params.destinationChainName}: ${filledByOrderId.size}`);

// -------------------- 3) Diff: Opened on Arb but NOT Filled on Destination Chain --------------------
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

// -------------------- 5) Solver repayment time on Source Chain --------------------
// Start: SettlementVerificationRequested(orderId, requestId)
// End:   Settled(orderId, settlementReceiver)
  const repayStartByOrderId = new Map<string, RepaymentStartEntry>();
  const repayEndByOrderId = new Map<string, RepaymentEndEntry>();

// 5.a) Collect SettlementVerificationRequested (start) on Source Chain
  for (let start = params.sourceChainFromBlock; start <= params.sourceChainLatest; start += step + 1) {
    const end = Math.min(params.sourceChainLatest, start + step);

    const logs = await params.sourceChainProvider.getLogs({
      address: params.sourceChainErc7683Address,
      fromBlock: start,
      toBlock: end,
      topics: [svrTopic0],
    });

    for (const log of logs) {
      const orderId = norm(log.topics[1]!); // indexed orderId
      if (!repayStartByOrderId.has(orderId)) {
        const blk = await params.sourceChainProvider.getBlock(log.blockNumber);
        const blockTimestamp = Number(blk?.timestamp ?? 0);

        repayStartByOrderId.set(orderId, {
          orderId,
          blockNumber: log.blockNumber,
          blockTimestamp,
          txHash: log.transactionHash,
          logIndex: log.index,
        });
      }
    }
  }

  console.log(`SettlementVerificationRequested unique orderIds on ${params.sourceChainName}: ${repayStartByOrderId.size}`);

// 5.b) Collect Settled (end) on Source Chain
  for (let start = params.sourceChainFromBlock; start <= params.sourceChainLatest; start += step + 1) {
    const end = Math.min(params.sourceChainLatest, start + step);

    const logs = await params.sourceChainProvider.getLogs({
      address: params.sourceChainErc7683Address,
      fromBlock: start,
      toBlock: end,
      topics: [settledTopic0],
    });

    for (const log of logs) {
      const orderId = norm(log.topics[1]!); // indexed orderId
      if (!repayEndByOrderId.has(orderId)) {
        const blk = await params.sourceChainProvider.getBlock(log.blockNumber);
        const blockTimestamp = Number(blk?.timestamp ?? 0);

        repayEndByOrderId.set(orderId, {
          orderId,
          blockNumber: log.blockNumber,
          blockTimestamp,
          txHash: log.transactionHash,
          logIndex: log.index,
        });
      }
    }
  }

  console.log(`Settled unique orderIds on ${params.sourceChainName}: ${repayEndByOrderId.size}`);

// 5.c) Repayment time stats (start->end) per orderId
  const repaymentDurationsSec: number[] = [];
  let repayMatchedCount = 0;

  for (const [orderId, startEntry] of repayStartByOrderId.entries()) {
    const endEntry = repayEndByOrderId.get(orderId);
    if (endEntry) {
      const delta = endEntry.blockTimestamp - startEntry.blockTimestamp;
      if (Number.isFinite(delta) && delta >= 0) {
        repaymentDurationsSec.push(delta);
        repayMatchedCount++;
      }
    }
  }

  if (repayMatchedCount === 0) {
    console.log(`No matched SettlementVerificationRequested -> Settled pairs within the specified ${params.sourceChainName} range. Skipping repayment stats.`);
  } else {
    let fastest = Infinity;
    let slowest = -Infinity;
    let sum = 0;

    for (const d of repaymentDurationsSec) {
      if (d < fastest) fastest = d;
      if (d > slowest) slowest = d;
      sum += d;
    }
    const avg = sum / repaymentDurationsSec.length;

    console.log("Matched repayment pairs (verification->settled):", repayMatchedCount);
    console.log("Fastest solver repayment time (s):", fastest);
    console.log("Slowest solver repayment time (s):", slowest);
    console.log("Average solver repayment time (s):", avg);
  }

// -------------------- 5.d) Unsettled SettlementVerificationRequested (no Settled) --------------------
  const unsettledRepayStarts: { orderId: string; txHash: string }[] = [];
  for (const [orderId, startEntry] of repayStartByOrderId.entries()) {
    if (!repayEndByOrderId.has(orderId)) {
      unsettledRepayStarts.push({ orderId, txHash: startEntry.txHash });
    }
  }

  console.log("Unsettled SettlementVerificationRequested count:", unsettledRepayStarts.length);
  console.log("Unsettled SettlementVerificationRequested:", JSON.stringify(unsettledRepayStarts, null, 2));
}
