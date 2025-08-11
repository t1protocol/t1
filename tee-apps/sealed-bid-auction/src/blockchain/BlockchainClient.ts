import {type Chain, createPublicClient, http} from "viem";

export class BlockchainClient {
    private _client;

    public constructor(rpcUrl: string, chain: Chain, pollingInterval: number) {
        this._client = createPublicClient({
            chain,
            transport: http(rpcUrl),
            pollingInterval
        });
    }

    public get client() {
        return this._client;
    }
}