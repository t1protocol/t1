import {type Chain, createPublicClient, createWalletClient, http} from "viem";
import {privateKeyToAccount} from "viem/accounts";

export class ViemBlockchainClient {
    private _publicClient;
    private _walletClient;

    public constructor(rpcUrl: string, chain: Chain, pollingInterval: number, signerKey?: `0x${string}`) {
        this._publicClient = createPublicClient({
            chain,
            transport: http(rpcUrl),
            pollingInterval
        });
        
        if (signerKey) {
            const account = privateKeyToAccount(signerKey);

            this._walletClient = createWalletClient({
                account,
                chain: chain,
                transport: http(rpcUrl)
            });
        }
    }

    public get publicClient() {
        return this._publicClient;
    }

    public get walletClient() {
        if (!this._walletClient) {
            throw new Error("Wallet client not initialised!");
        }

        return this._walletClient;
    }
}