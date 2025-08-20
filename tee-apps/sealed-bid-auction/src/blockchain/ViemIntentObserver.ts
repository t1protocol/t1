import {
    decodeAbiParameters, encodeAbiParameters, keccak256,
    parseEventLogs,
    trim,
    type WatchEventOnLogsParameter
} from "viem"

import type {AuctionService} from "../core/AuctionService.ts";
import {
    OPEN_INTENT_ABI_EVENT,
    ORDER_DATA_ABI_PARAMETERS_WRAPPED_IN_TUPLE,
    type OrderData,
} from "./types.ts";
import type {AuctionApiServer} from "../api/AuctionApiServer.ts";
import { serialize, WinstonLogger} from "../utils/WinstonLogger.ts";
import type {BlockchainClient} from "./BlockchainClient.ts";
import type {ViemAuctionCommiter} from "./ViemAuctionCommiter.ts";
import type {AuctionResult} from "../api/types.ts";

export class ViemIntentObserver {
    private logger: WinstonLogger;

    constructor(private readonly blockchainClient: BlockchainClient,
                private readonly auctionCommiter: ViemAuctionCommiter,
                private readonly t1Erc7683ContractAddress: `0x${string}`,
                private readonly auctionService: AuctionService,
                private readonly apiServer: AuctionApiServer,
                private readonly auctionPollingInterval: number = 500
    ) {
        this.logger = new WinstonLogger(`${ViemIntentObserver.name}[${this.blockchainClient.publicClient.chain.name}]`);
    }

    public start() {
        this.blockchainClient.publicClient.watchEvent({
            address: this.t1Erc7683ContractAddress,
            event: OPEN_INTENT_ABI_EVENT,
            onLogs: logs => this.processIntentLogs(logs)
        });

        this.logger.info(`Watching for Open Intent events on chain [${this.blockchainClient.publicClient.chain.name}] and contract [${this.t1Erc7683ContractAddress}]`);
    }

    private async processIntentLogs(logs: WatchEventOnLogsParameter) {
        this.logger.info('Intent was Open-ed!');

        const parsedLogs = parseEventLogs({
            abi: [OPEN_INTENT_ABI_EVENT],
            logs
        });

        for (const order of parsedLogs) {
            for (const fillInstruction of order.args.resolvedOrder.fillInstructions) {
                const [decodedOrder] = decodeAbiParameters(ORDER_DATA_ABI_PARAMETERS_WRAPPED_IN_TUPLE, fillInstruction.originData);

                const orderData = decodedOrder as OrderData;

                await this.runAuctionAndNotifySolver({
                    sender: trim(orderData.sender),
                    recipient: trim(orderData.recipient),
                    inputToken: trim(orderData.inputToken),
                    outputToken: trim(orderData.outputToken),
                    amountIn: BigInt(orderData.amountIn),
                    minAmountOut: BigInt(orderData.minAmountOut),
                    senderNonce: Number(orderData.senderNonce),
                    originDomain: orderData.originDomain,
                    destinationDomain: orderData.destinationDomain,
                    destinationSettler: trim(orderData.destinationSettler),
                    fillDeadline: orderData.fillDeadline,
                    closedAuction: orderData.closedAuction,
                    data: orderData.data,
                }, order.args.orderId);
            }
        }
    }

    private async runAuctionAndNotifySolver(orderData: OrderData, orderId: string) {
        this.logger.info(`Running auction for order ${orderId}`);

        this.logger.debug(`Running auction for orderData ${serialize(orderData)}`);

        while (Date.now() / 1000 < orderData.fillDeadline) {
            const winningPrice = this.auctionService.auction(orderData.inputToken, orderData.outputToken, orderData.amountIn);

            this.logger.debug(`Auction winner: ${serialize(winningPrice)}`);

            if (winningPrice !== null && winningPrice.amountOut >= orderData.minAmountOut) {

                const result: AuctionResult = {
                    type: "winning-bid",
                    settlementReceiverAddress: winningPrice.settlementReceiverAddress,
                    amountOut: winningPrice.amountOut,
                    orderId,
                    signature: await this.signAuctionResult(
                        BigInt(orderId), winningPrice.settlementReceiverAddress as `0x${string}`, winningPrice.amountOut
                    )
                }

                await this.apiServer.notifySolvers(result, this.blockchainClient.publicClient.chain.id);
                const txHash = await this.auctionCommiter.commitWinnerBid(result);

                this.logger.info(`I finished auction for orderId=[${orderId}] , notified solvers amd sent winningBid using tx=[${txHash}]`);
                break;
            }
            
            await new Promise((resolve) => setTimeout(resolve, this.auctionPollingInterval));
        }
    }

    private async signAuctionResult(orderId: bigint, winningSolver: `0x${string}`, amountOut: bigint) : Promise<string> {
        const encoded = encodeAbiParameters(
            [
                { type: 'uint256', name: 'orderId' },
                { type: 'address', name: 'winningSolver' },
                { type: 'uint256', name: 'bidAmountOut' },
            ],
            [orderId, winningSolver, amountOut],
        )

        const hash = keccak256(encoded);

        return await this.blockchainClient.signMessage(hash);
    }
}
