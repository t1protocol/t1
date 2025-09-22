import {
    type Chain,
    createPublicClient,
    createWalletClient,
    http,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { Abi } from "viem";
import { erc20Abi } from "viem";

export class T1ERC7683Client {
    public publicClient;
    private walletClient;

    private t1Erc7683Contract;

    constructor(
        rpcUrl: string,
        contractAddress: `0x${string}`,
        abi: Abi,
        privateKey: `0x${string}`,
        chain: Chain
    ) {
        this.publicClient = createPublicClient({
            chain,
            transport: http(rpcUrl),
        });

        this.walletClient = createWalletClient({
            account: privateKeyToAccount(privateKey),
            chain,
            transport: http(rpcUrl),
        });

        this.t1Erc7683Contract = {
            address: contractAddress,
            abi,
        };
    }

    public async getErc20Balance(token: `0x${string}`): Promise<bigint> {
        return this.publicClient.readContract({
            address: token,
            abi: erc20Abi,
            functionName: "balanceOf",
            args: [this.t1Erc7683Contract.address],
        }) as Promise<bigint>;
    }

    public async isOpenPaused(): Promise<boolean> {
        return this.publicClient.readContract({
            ...this.t1Erc7683Contract,
            functionName: "openPaused",
        }) as Promise<boolean>;
    }

    public async pauseOpen() {
        return this.walletClient.writeContract({
            ...this.t1Erc7683Contract,
            functionName: "pauseOpen",
            args: [],
        });
    }

    public async unpauseOpen() {
        return this.walletClient.writeContract({
            ...this.t1Erc7683Contract,
            functionName: "unpauseOpen",
            args: [],
        });
    }

}
