import {
    type Chain,
    createPublicClient,
    decodeAbiParameters,
    http,
    parseAbi,
    parseAbiItem,
    parseAbiParameters,
    parseEventLogs,
    type WatchEventOnLogsParameter
} from "viem"

import type {AuctionService} from "../core/AuctionService.ts";
import {
    convertSolidityOrderDataToTypescriptOrderData,
    FILL_INSTRUCTION_ABI_PARAMETERS,
    OPEN_INTENT_EVENT_SIGNATURE,
    ORDER_DATA_ABI_PARAMETERS,
    type OrderData,
    RESOLVER_ORDER_ABI_PARAMETERS
} from "./types.ts";
import type {AuctionApiServer} from "../api/AuctionApiServer.ts";
import {WinstonLogger} from "../utils/WinstonLogger.ts";

export class ViemIntentObserver {
    private logger: WinstonLogger;

    private readonly client;

    constructor(rpcUrl: string,
                private readonly chain: Chain,
                pollingInterval: number,
                private readonly t1Erc7683ContractAddress: `0x${string}`,
                private readonly auctionService: AuctionService,
                private readonly apiServer: AuctionApiServer,
                private readonly auctionPollingInterval: number = 500
    ) {
        this.logger = new WinstonLogger(`${ViemIntentObserver.name}[${chain.name}]`);
        this.client = createPublicClient({
            chain,
            transport: http(rpcUrl),
            pollingInterval
        });
    }

    public start() {
        this.client.watchEvent({
            address: this.t1Erc7683ContractAddress,
            event: parseAbiItem(OPEN_INTENT_EVENT_SIGNATURE),
            onLogs: logs => this.processIntentLogs(logs)
        });

        this.logger.info(`Watching for Open Intent events on chain [${this.chain.name}] and contract [${this.t1Erc7683ContractAddress}]`);
    }

    private async processIntentLogs(logs: WatchEventOnLogsParameter) {
        this.logger.info('Intent was Open-ed!');

        const parsedLogs = parseEventLogs({
            abi: parseAbi([OPEN_INTENT_EVENT_SIGNATURE]),
            logs
        });

        const auctionPromises: Promise<void>[] = [];

        for (const order of parsedLogs) {
            const resolvedOrder = decodeAbiParameters(parseAbiParameters(RESOLVER_ORDER_ABI_PARAMETERS), order.args.resolvedOrder);
            const fillInstructions = decodeAbiParameters(parseAbiParameters(FILL_INSTRUCTION_ABI_PARAMETERS), resolvedOrder[7] as `0x${string}`);
            const orderDatas = fillInstructions.map(fillInstruction => decodeAbiParameters(parseAbiParameters(ORDER_DATA_ABI_PARAMETERS), fillInstruction as `0x${string}`));

            for (const orderData of orderDatas.map(solidityOrderData => convertSolidityOrderDataToTypescriptOrderData(solidityOrderData))) {
                auctionPromises.push(this.runAuctionAndNotifySolver(orderData, order.args.orderId));
            }
        }

        await Promise.all(auctionPromises);
    }

    private async runAuctionAndNotifySolver(orderData: OrderData, orderId: string) {
        while (Date.now() < orderData.fillDeadline) {
            const winningPrice = this.auctionService.auction(orderData.inputToken, orderData.outputToken, orderData.amountIn);

            if (winningPrice !== null && winningPrice.amountOut >= orderData.minAmountOut) {
                this.apiServer.publishAuctionResult(winningPrice!, orderId, orderData, this.chain.id);
                break;
            }

            await new Promise((resolve) => setTimeout(resolve, this.auctionPollingInterval));
        }
    }
}