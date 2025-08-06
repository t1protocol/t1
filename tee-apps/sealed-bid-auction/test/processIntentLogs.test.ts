import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeAll, expect, test, vi } from "vitest";
import { ViemIntentObserver } from "../src/blockchain/ViemIntentObserver";
import { arbitrumSepolia } from "viem/chains";

/* ---------- 1. load logs from the Foundry broadcast file ---------- */
const fixturePath = resolve(__dirname, "fixtures/arb-sepolia-run.json");
const raw = JSON.parse(readFileSync(fixturePath, "utf-8"));

// every transaction receipt → its logs
const logs =
  (raw.receipts ?? raw.transactions.map((t: any) => t.receipt)).flatMap(
    (r: any) => r.logs,
  );


/* ---------- 2. cheap mocks so nothing really goes on‑chain ---------- */
const auctionSvc = { auction: vi.fn().mockResolvedValue({ amountOut: 100n, solver: "0x0" }) };
const apiServer = { publishAuctionResult: vi.fn() };

/* ---------- 3. system‑under‑test ----------------------------------- */
const intentContract = "0xc7b348fa0a01e292818df7226cfbaa86d0a391a9";
const observer = new ViemIntentObserver(
  process.env.ARBITRUM_SEPOLIA_RPC ?? "https://sepolia-rollup.arbitrum.io/rpc",
  arbitrumSepolia,
  /* poll */ 1_000,
  intentContract,
  auctionSvc as any,
  apiServer  as any,
);

beforeAll(async () => {
  // call the freshly‑public method with the captured logs
  await observer.processIntentLogs(logs as any);
});

test("runs the sealed‑bid flow end‑to‑end", () => {
  expect(auctionSvc.auction).toHaveBeenCalled();
  expect(apiServer.publishAuctionResult).toHaveBeenCalledWith(
    expect.any(Object),                                 // winning price
    "0x2069f1cda7f58c735e85a9b24221cd59f7fa1e3c43020e23460e946e81d1f732",
    expect.any(Object),                                 // decoded order data
    421614,                                             // chainId
  );
});

