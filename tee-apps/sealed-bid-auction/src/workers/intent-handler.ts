import { decodeAbiParameters, parseAbiParameters } from "viem";
import { AuctionIntentsWorker } from "./auction-intents-worker.ts";
import {
  convertSolidityOrderDataToTypescriptOrderData,
  FILL_INSTRUCTION_ABI_PARAMETERS,
  RESOLVER_ORDER_ABI_PARAMETERS,
  ORDER_DATA_ABI_PARAMETERS,
} from "../utils/order-conversion.ts";

export async function handleOpenIntentLogs(
  this: AuctionIntentsWorker,
  parsedLogs: readonly { args: { orderId: `0x${string}`; resolvedOrder: `0x${string}` } }[],
): Promise<void> {
  const auctionPromises: Promise<void>[] = [];

  for (const order of parsedLogs) {
    let orderDatas: readonly unknown[] = [];
    try {
      const resolvedOrder = decodeAbiParameters(
        parseAbiParameters(RESOLVER_ORDER_ABI_PARAMETERS),
        order.args.resolvedOrder,
      );
      // unwrap the single returned parameter so `fillInstructions` is really a tuple[]
const [fillInstructions] = decodeAbiParameters(
  parseAbiParameters(FILL_INSTRUCTION_ABI_PARAMETERS),
  resolvedOrder[7] as `0x${string}`,
);

// pass ONLY the originData (fi[2]) to the inner decoder
orderDatas = fillInstructions.map((fi) =>
  decodeAbiParameters(
    parseAbiParameters(ORDER_DATA_ABI_PARAMETERS),
    fi[2] as `0x${string}`,
  ),
);

    } catch {
      // Some chains emit resolvedOrder as encoded OrderData directly
      const stripped = ("0x" + order.args.resolvedOrder.slice(66)) as `0x${string}`;
      orderDatas = [
        decodeAbiParameters(parseAbiParameters(ORDER_DATA_ABI_PARAMETERS), stripped),
      ];
    }

    for (const solidityOrderData of orderDatas) {
      const tsOrder = convertSolidityOrderDataToTypescriptOrderData(
        solidityOrderData as any,
      );
      auctionPromises.push(this.runAuctionAndNotifySolver(tsOrder, order.args.orderId));
    }
  }
  await Promise.allSettled(auctionPromises);
}
