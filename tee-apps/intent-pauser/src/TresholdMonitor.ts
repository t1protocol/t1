import { T1ERC7683Client } from "./T1ERC7683Client";

export class ThresholdMonitor {
    constructor(
        private readonly client: T1ERC7683Client,
        private readonly monitoredErc20Tokens: { token: `0x${string}`; decimals: number; symbol: string }[],
        private readonly pauseUsdThreshold: number,
        private readonly unpauseUsdThreshold: number,
        private readonly ethPriceFallback: number
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
            console.log(`[${this.client.publicClient.chain.name}] Contract balance = [${total} USD]. Paused = [${paused}] . No action taken.`);
            return null;
        }
    }

    private async getTotalBalanceUsd(): Promise<bigint> {
        const balances = await Promise.all(
            this.monitoredErc20Tokens.map(async ({ token, decimals, symbol }) => {
                const rawBal = await this.client.getErc20Balance(token);
                const normalized = rawBal / 10n ** BigInt(decimals);
                const price = await this.getUsdPrice(symbol);
                return normalized * BigInt(price);
            })
        );

        return balances.reduce((a, b) => a + b, 0n);
    }

    private async getUsdPrice(symbol: string): Promise<number> {
        let result = 0;

        if (symbol === "USDC") result = 1;

        if (symbol === "WETH") {
            const coingeckoPrice = await this.readEthPriceFromCoingecko();

            coingeckoPrice ? result = coingeckoPrice : result = this.ethPriceFallback;
        }

        return result;
    }

    private async readEthPriceFromCoingecko(): Promise<number | null> {
        try {
            const res = await fetch(
                "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd"
            );
            const data = await res.json() as { symbol: string, price: string };

            return Number(data.price);
        } catch (e) {
            console.error("Error fetching ETH price from Coingecko:", e);
            return null;
        }
    }
}
