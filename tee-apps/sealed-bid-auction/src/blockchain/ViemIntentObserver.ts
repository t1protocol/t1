import {
    type Chain,
    createPublicClient, decodeFunctionResult,
    http,
    parseAbi,
    parseAbiItem,
    parseEventLogs,
    type WatchEventOnLogsParameter
} from "viem"

import type {AuctionService} from "../core/AuctionService.ts";
import t1Erc7683Abi from "../../../../contracts/artifacts/src/T1ERC7683.sol/T1ERC7683.json";
import type {OrderData} from "./types.ts";
import type {SealedBidAuctionApiServer} from "../api/SealedBidAuctionApiServer.ts";

export class ViemIntentObserver {
    private readonly OPEN_INTENT_EVENT_SIGNATURE = 'event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder)';

    private readonly client;

    constructor(rpcUrl: string,
                private readonly chain: Chain,
                pollingInterval: number,
                private readonly t1Erc7683ContractAddress: `0x${string}`,
                private readonly auctionService: AuctionService,
                private readonly apiServer: SealedBidAuctionApiServer
    ) {
        this.client = createPublicClient({
            chain,
            transport: http(rpcUrl),
            pollingInterval
        });
    }

    public start() {
        this.client.watchEvent({
            address: this.t1Erc7683ContractAddress,
            event: parseAbiItem(this.OPEN_INTENT_EVENT_SIGNATURE),
            onLogs: logs => this.processIntentLogs(logs)
        })
    }

    private async processIntentLogs(logs: WatchEventOnLogsParameter) {
        const parsedLogs = parseEventLogs({
            abi: parseAbi([this.OPEN_INTENT_EVENT_SIGNATURE]),
            logs
        });

        const auctionPromises: Promise<void>[] = [];

        for (const order of parsedLogs) {
            const encodedReadResult = (await this.client.readContract({
                address: this.t1Erc7683ContractAddress,
                abi: t1Erc7683Abi.abi,
                functionName: 'openOrders',
                args: [order.args.orderId]
            })) as `0x${string}`;

            const orderData: OrderData = JSON.parse(decodeFunctionResult({
                abi: t1Erc7683Abi.abi,
                functionName: 'openOrders',
                data: encodedReadResult
            }) as string);

            auctionPromises.push(this.runAuctionAndNotifySolver(orderData, order.args.orderId, order.args.resolvedOrder as string));
        }

        await Promise.all(auctionPromises);
    }

    private async runAuctionAndNotifySolver(orderData: OrderData, orderId: string, resolvedOrder: string) {
        while(Date.now() < orderData.fillDeadline) {
            const winningPrice = this.auctionService.auction(orderData.inputToken, orderData.outputToken, orderData.amountIn);

            if (winningPrice !== null && winningPrice.amountOut >= orderData.minAmountOut) {
                this.apiServer.publishAuctionResult(winningPrice!, orderId, resolvedOrder, this.chain.id);
                break;
            }

            await new Promise((resolve) => setTimeout(resolve, 100));
        }
    }
}