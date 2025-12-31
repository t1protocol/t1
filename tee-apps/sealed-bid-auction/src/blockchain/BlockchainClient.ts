import {type Chain, createPublicClient, webSocket} from "viem";
import {privateKeyToAccount} from "viem/accounts";

export class BlockchainClient {
    private _publicClient;

    public constructor(
        wsUrl: string,
        chain: Chain,
        private readonly signerKey?: `0x${string}`,
    ) {
        this._publicClient = createPublicClient({
            chain: chain,
            transport: webSocket(wsUrl, {
                reconnect: {
                  attempts: Infinity,
                  delay: 1000,
                },
                keepAlive: {
                  interval: 15000,
                },
            }),
        });
    }

    public get publicClient() {
        return this._publicClient;
    }

    public async signMessage(message: string): Promise<`0x${string}`> {
        if (!this.signerKey) {
            throw new Error("Signer key not initialised!");
        }

        const account = privateKeyToAccount(this.signerKey);

        return await account.signMessage({
            message,
        });
    }

    public async signTypedData(
        domain: Record<string, any>,
        types: Record<string, any>,
        message: Record<string, any>
    ): Promise<`0x${string}`> {
        if (!this.signerKey) {
            throw new Error("Signer key not initialised!");
        }

        const account = privateKeyToAccount(this.signerKey);

        const primaryType = Object.keys(types)[0];
        if (!primaryType) {
            throw new Error("No types provided for EIP-712 signing");
        }

        return await account.signTypedData({
            domain,
            types,
            primaryType,
            message,
        });
    }
}
