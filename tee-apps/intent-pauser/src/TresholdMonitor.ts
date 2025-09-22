import { T1ERC7683Client } from "./T1ERC7683Client";

export class ThresholdMonitor {

    constructor(
        private readonly client: T1ERC7683Client,
        private readonly monitoredErc20Tokens: { token: `0x${string}`; decimals: number; symbol: string }[],
        private readonly pauseUsdThreshold: number,
        private readonly unpauseUsdThreshold: number,
    ) { }

    public async pauseOrUnpauseIfNeeded(): Promise<`0x${string}` | null> {
        const total = await this.getTotalBalanceUsd();
        const paused = await this.client.isOpenPaused();

        if (!paused && total > this.pauseUsdThreshold) {
            console.log(
                `Threshold exceeded: ${total} > ${this.pauseUsdThreshold}, calling pauseOpen()...`
            );
            return this.client.pauseOpen();
        } else if (paused && total < this.unpauseUsdThreshold) {
            console.log(
                `Returned under threshold: ${total} < ${this.unpauseUsdThreshold}, calling unpauseOpen()...`
            );
            return this.client.unpauseOpen();
        } else {
            console.log(`Contract balance = [${total} USD]. Paused = [${paused}] . No action taken.`);
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
