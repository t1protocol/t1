import {createPublicClient, http, parseAbiItem} from "viem"
import {arbitrumSepolia} from "viem/chains"

import type {IntentObserver} from "./IntentObserver.ts";

export class ArbitrumSepoliaIntentObserver implements IntentObserver {
    private readonly client;

    constructor(rpcUrl: string, pollingInterval: number) {
        this.client = createPublicClient({
            chain: arbitrumSepolia,
            transport: http(rpcUrl),
            pollingInterval
        });
    }

    public start(t1Erc7683ContractAddress: `0x${string}`) {
        this.client.watchEvent({
            address: t1Erc7683ContractAddress,
            event: parseAbiItem('event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder)'),
            onLogs: logs => console.log(logs)
        })
    }
}