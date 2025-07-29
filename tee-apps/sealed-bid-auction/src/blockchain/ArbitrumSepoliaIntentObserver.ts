import {createPublicClient, http, parseAbi, parseAbiItem, parseEventLogs, type WatchEventOnLogsParameter} from "viem"
import {arbitrumSepolia} from "viem/chains"

import type {IntentObserver} from "./IntentObserver.ts";
import type {AuctionService} from "../core/AuctionService.ts";

export class ArbitrumSepoliaIntentObserver implements IntentObserver {
    private readonly OPEN_INTENT_EVENT_SIGNATURE = 'event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder)';

    private readonly client;

    constructor(rpcUrl: string, pollingInterval: number, private readonly auctionService: AuctionService) {
        this.client = createPublicClient({
            chain: arbitrumSepolia,
            transport: http(rpcUrl),
            pollingInterval
        });
    }

    public start(t1Erc7683ContractAddress: `0x${string}`) {
        this.client.watchEvent({
            address: t1Erc7683ContractAddress,
            event: parseAbiItem(this.OPEN_INTENT_EVENT_SIGNATURE),
            onLogs: logs => this.parseLogsAndStartAuction(logs)
        })
    }

    private parseLogsAndStartAuction(logs: WatchEventOnLogsParameter) {
        const parsedLogs = parseEventLogs({
            abi: parseAbi([this.OPEN_INTENT_EVENT_SIGNATURE]),
            logs
        });

        parsedLogs.map(log => {
            const resolvedOrder = log.args.resolvedOrder;
            // do sth with resolved order
        });
    }
}