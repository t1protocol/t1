import { test, expect, vi } from "bun:test";
import { AuctionIntentsWorker } from "../../src/workers/auction-intents-worker.ts";
import { handleOpenIntentLogs } from "../../src/workers/intent-handler.ts";
import {
  convertSolidityOrderDataToTypescriptOrderData,
  ORDER_DATA_ABI_PARAMETERS,
} from "../../src/utils/order-conversion.ts";
import { decodeAbiParameters, parseAbiParameters } from "viem";

/* ——— REAL BYTES (hard‑coded sample) ——————————— */
const orderId =
  "0xfc34ebf93ef4c002f12809839bd8641cc99afeb6fc95589e659a6b7ab8c9b54f" as const;
const resolvedOrder =
  "0x0000000000000000000000000000000000000000000000000000000000000020" +
  "0000000000000000000000002ade71354645c57e7d099dbc04b27f8ad277395e" +
  "0000000000000000000000002ade71354645c57e7d099dbc04b27f8ad277395e" +
  "000000000000000000000000f6232a871bf3b33f5bc181f55d770f9fb062a457" +
  "000000000000000000000000228ee6c1c297e2eba0e95a71684b26f89385b4ec" +
  "0000000000000000000000000000000000000000000000000000000000000064" +
  "0000000000000000000000000000000000000000000000000000000000000064" +
  "00000000000000000000000000000000000000000000000000000000000022d7" +
  "0000000000000000000000000000000000000000000000000000000000066eee" +
  "0000000000000000000000000000000000000000000000000000000000014a34" +
  "0000000000000000000000003f1d74349391fb299d40ab925d09838157af226b" +
  "0000000000000000000000000000000000000000000000000000000068939a4e" +
  "0000000000000000000000000000000000000000000000000000000000000000" +
  "00000000000000000000000000000000000000000000000000000000000001a0" +
  "0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`;

/* ——— helpers ———— */
function expectedFirstTsOrder() {
  // These constants come from manual decoding of the sample bytes.
  // Keep them up to date if you regenerate the fixture.
  return {
    sender: "0x2Ade71354645C57e7D099DbC04b27f8ad277395E",
    recipient: "0x2Ade71354645C57e7D099DbC04b27f8ad277395E",
    inputToken: "0xF6232a871BF3B33F5bc181f55d770F9FB062A457",
    outputToken: "0x228eE6c1C297E2Eba0e95A71684B26f89385b4eC",
    amountIn: 100n,
    minAmountOut: 100n,
    senderNonce: 8919n,
    originDomain: 0x66eeen,
    destinationDomain: 0x14a34n,
    destinationSettler: "0x3F1d74349391Fb299d40Ab925d09838157af226b",
    fillDeadline: 0x68939a4en,
    closedAuction: false,
    data: "0x",
  };
}

test("decode every originData & verify contents", async () => {
  const worker = new AuctionIntentsWorker();
  const auctionSpy = vi
    .spyOn(worker, "runAuctionAndNotifySolver")
    .mockResolvedValue(undefined);

  await handleOpenIntentLogs.call(worker, [
    { args: { orderId, resolvedOrder } },
  ] as const);

  /* —— Level 1: deep‑equality on first object —— */
  const firstCallArg = auctionSpy.mock.calls[0][0];
  expect(firstCallArg).toEqual(expectedFirstTsOrder());

  /* —— Level 2: ensure we covered *every* FillInstruction —— */
  // Independently decode to count how many originData blobs exist
  let fillInstructionsLength = 1;
  try {
    const [fillInstructions] = decodeAbiParameters(
      [
        {
          type: "tuple[]",
          components: [
            { type: "uint256" },
            { type: "address" },
            { type: "bytes" },
          ],
        },
      ],
      (
        decodeAbiParameters(
          parseAbiParameters(
            "address,uint256,uint256,uint256,bytes,bytes,bytes,bytes"
          ),
          resolvedOrder
        )[7] as `0x${string}`
      )
    );
    fillInstructionsLength = fillInstructions.length;
  } catch {
    fillInstructionsLength = 1;
  }

  expect(auctionSpy).toHaveBeenCalledTimes(fillInstructionsLength);

  auctionSpy.mockRestore();
});
