import {describe, it, expect, jest, afterEach} from "@jest/globals";
import {ViemIntentObserver} from "../src/blockchain/ViemIntentObserver.ts";
import {convertSolidityOrderDataToTypescriptOrderData,
    RESOLVER_ORDER_ABI_PARAMETERS,
    ORDER_DATA_ABI_PARAMETERS,
    FILL_INSTRUCTION_ABI_PARAMETERS} from "../src/blockchain/types.ts";
import * as viem from "viem";
import {mainnet} from "viem/chains";
import fc from "fast-check";

describe("processIntentLogs integration", () => {
    afterEach(() => {
        jest.restoreAllMocks();
    });
    it("should run auction and notify solver for each order", async () => {
        const auctionService = { auction: () => null } as any;
        const apiServer = { publishAuctionResult: () => {} } as any;
        const observer = new ViemIntentObserver(
            "http://localhost", mainnet, 1000,
            "0x0000000000000000000000000000000000000000", auctionService, apiServer, 100
        );

        const orderAbi = viem.parseAbiParameters(ORDER_DATA_ABI_PARAMETERS);
        const order1Tuple: any = [
            "0x0000000000000000000000000000000000000001",
            "0x0000000000000000000000000000000000000002",
            "0x0000000000000000000000000000000000000003",
            "0x0000000000000000000000000000000000000004",
            1n, 2n, 3n, 4n, 5n,
            "0x0000000000000000000000000000000000000005",
            7n, false, "0x"
        ];
        const order2Tuple: any = [
            "0x0000000000000000000000000000000000000011",
            "0x0000000000000000000000000000000000000012",
            "0x0000000000000000000000000000000000000013",
            "0x0000000000000000000000000000000000000014",
            10n, 20n, 30n, 40n, 50n,
            "0x0000000000000000000000000000000000000015",
            70n, false, "0x"
        ];
        const order1Encoded = viem.encodeAbiParameters(orderAbi, order1Tuple);
        const order2Encoded = viem.encodeAbiParameters(orderAbi, order2Tuple);
        const order1Ts = convertSolidityOrderDataToTypescriptOrderData(
            viem.decodeAbiParameters(orderAbi, order1Encoded) as any
        );
        const order2Ts = convertSolidityOrderDataToTypescriptOrderData(
            viem.decodeAbiParameters(orderAbi, order2Encoded) as any
        );

        const bytesArrayAbi = viem.parseAbiParameters("bytes[]");
        const fill1Encoded = viem.encodeAbiParameters(bytesArrayAbi, [[order1Encoded]]);
        const fill2Encoded = viem.encodeAbiParameters(bytesArrayAbi, [[order2Encoded]]);

        const resolverAbi = viem.parseAbiParameters(RESOLVER_ORDER_ABI_PARAMETERS);
        const resolvedOrder1 = viem.encodeAbiParameters(resolverAbi, ["user", 1n, 0n, 0n, "0x", "0x", "0x", fill1Encoded]);
        const resolvedOrder2 = viem.encodeAbiParameters(resolverAbi, ["user", 1n, 0n, 0n, "0x", "0x", "0x", fill2Encoded]);

        jest.spyOn(viem, "parseEventLogs").mockReturnValue([
            { args: { resolvedOrder: resolvedOrder1, orderId: "0xaaa" } },
            { args: { resolvedOrder: resolvedOrder2, orderId: "0xbbb" } }
        ] as any);

        const runSpy = jest.spyOn(observer as any, "runAuctionAndNotifySolver").mockResolvedValue();

        await (observer as any).processIntentLogs([]);

        expect(runSpy).toHaveBeenCalledTimes(2);
        expect(runSpy).toHaveBeenNthCalledWith(1, order1Ts, "0xaaa");
        expect(runSpy).toHaveBeenNthCalledWith(2, order2Ts, "0xbbb");
    });
});

describe("property based decoding of orderData", () => {
    fc.configureGlobal({ numRuns: 100 });

    it("round trips random orders", async () => {
        const auctionService = { auction: () => null } as any;
        const apiServer = { publishAuctionResult: () => {} } as any;
        const observer = new ViemIntentObserver(
            "http://localhost", mainnet, 1000,
            "0x0000000000000000000000000000000000000000", auctionService, apiServer, 100
        );

        const addressArb = fc.uint8Array({ minLength: 20, maxLength: 20 }).map(a => viem.toHex(a));
        const bigintArb = fc.bigInt({ min: 0n, max: (1n << 128n) - 1n });
        const dataArb = fc.uint8Array({ maxLength: 256 }).map(a => viem.toHex(a));
        const orderTupleArb = fc.tuple(
            addressArb, addressArb, addressArb, addressArb,
            bigintArb, bigintArb, bigintArb, bigintArb, bigintArb,
            addressArb, bigintArb, fc.boolean(), dataArb
        );

        const orderAbi = viem.parseAbiParameters(ORDER_DATA_ABI_PARAMETERS);
        const bytesArrayAbi = viem.parseAbiParameters("bytes[]");
        const resolverAbi = viem.parseAbiParameters(RESOLVER_ORDER_ABI_PARAMETERS);

        let counter = 0;
        await fc.assert(fc.asyncProperty(orderTupleArb, async (tuple) => {
            const encoded = viem.encodeAbiParameters(orderAbi, tuple as any);
            const fillEncoded = viem.encodeAbiParameters(bytesArrayAbi, [[encoded]]);
            const resolverEncoded = viem.encodeAbiParameters(
                resolverAbi, ["user", 1n, 0n, 0n, "0x", "0x", "0x", fillEncoded]
            );

            counter++;
            const parseEventLogsSpy = jest.spyOn(viem, "parseEventLogs").mockReturnValue([
                { args: { resolvedOrder: resolverEncoded, orderId: `0x${counter.toString(16)}` } }
            ] as any);
            const runSpy = jest.spyOn(observer as any, "runAuctionAndNotifySolver").mockResolvedValue();

            await (observer as any).processIntentLogs([]);

            expect(runSpy).toHaveBeenCalledTimes(1);
            const orderObj = runSpy.mock.calls[0][0];
            const tupleFromObj: any = [
                orderObj.sender, orderObj.recipient, orderObj.inputToken, orderObj.outputToken,
                orderObj.amountIn, orderObj.minAmountOut, orderObj.senderNonce,
                orderObj.originDomain, orderObj.destinationDomain, orderObj.destinationSettler,
                orderObj.fillDeadline, orderObj.closedAuction, orderObj.data
            ];
            const reEncoded = viem.encodeAbiParameters(orderAbi, tupleFromObj);
            expect(reEncoded).toBe(encoded);

            parseEventLogsSpy.mockRestore();
            runSpy.mockRestore();
        }));
    });

    it("decodes real IntentSolved log fixture", async () => {
        const auctionService = { auction: () => null } as any;
        const apiServer = { publishAuctionResult: () => {} } as any;
        const observer = new ViemIntentObserver(
            "http://localhost", mainnet, 1000,
            "0x0000000000000000000000000000000000000000", auctionService, apiServer, 100
        );

        const resolvedOrder =
            "0x000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000000475736572000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000380000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" as const;

        const orderAbi = viem.parseAbiParameters(ORDER_DATA_ABI_PARAMETERS);
        const bytesArrayAbi = viem.parseAbiParameters("bytes[]");
        const resolverAbi = viem.parseAbiParameters(RESOLVER_ORDER_ABI_PARAMETERS);
        const decoded = viem.decodeAbiParameters(resolverAbi, resolvedOrder);
        const [fills] = viem.decodeAbiParameters(bytesArrayAbi, decoded[7] as `0x${string}`) as [`0x${string}`[]];
        const expectedOrder = convertSolidityOrderDataToTypescriptOrderData(
            viem.decodeAbiParameters(orderAbi, fills[0] as `0x${string}`) as any
        );

        jest.spyOn(viem, "parseEventLogs").mockReturnValue([
            { args: { resolvedOrder, orderId: "0xaaa" } }
        ] as any);
        const runSpy = jest.spyOn(observer as any, "runAuctionAndNotifySolver").mockResolvedValue();

        await (observer as any).processIntentLogs([]);

        expect(runSpy).toHaveBeenCalledWith(expectedOrder, "0xaaa");
    });
});
