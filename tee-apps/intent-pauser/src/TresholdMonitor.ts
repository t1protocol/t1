import { T1ERC7683Client } from "./T1ERC7683Client";

export class ThresholdMonitor {

    constructor(
        private readonly client: T1ERC7683Client,
        private readonly monitoredErc20Tokens: { token: `0x${string}`; decimals: number; symbol: string }[],
        private usdThreshold: number,
    ) { }

    public async pauseIfAboveThreshold(): Promise<`0x${string}` | null> {
        const total = await this.getTotalBalanceUsd();
        if (total > this.usdThreshold) {
            console.log(
                `Threshold exceeded: ${total} > ${this.usdThreshold}, calling pauseOpen()`
            );
            return this.client.pauseOpen();
        } else {
            console.log(`Contract balance = ${total} USD (below threshold)`);
            return null;
        }
    }

    private async getTotalBalanceUsd(): Promise<bigint> {
        const balances = await Promise.all(
            this.monitoredErc20Tokens.map(async ({ token, decimals, symbol }) => {
                const rawBal = await this.client.getErc20Balance(token);
                const normalized = rawBal / 10n ** BigInt(decimals);
                const price = await this.getUsdPrice(symbol);
                return normalized * price;
            })
        );

        return balances.reduce((a, b) => a + b, 0n);
    }

    private async getUsdPrice(symbol: string): Promise<bigint> {
        if (symbol === "WETH") return 4100n;
        if (symbol === "USDC") return 1n;
        return 0n;
    }
}
