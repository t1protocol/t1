import * as dotenv from "dotenv";
import {arbitrum, base} from "viem/chains";
import contractAbi from "../../contracts/artifacts/src/T1ERC7683.sol/T1ERC7683.json";
import {T1ERC7683Client} from "./src/T1ERC7683Client";
import {ThresholdMonitor} from "./src/TresholdMonitor.ts";

dotenv.config();

interface NetworkConfig {
    chain: any;
    rpcUrl: string;
    contractAddress: `0x${string}`;
    weth: `0x${string}`;
    usdc: `0x${string}`;
}

async function startMonitor(config: NetworkConfig, privateKey: `0x${string}`, thresholdUsd: number, pollIntervalMs: number) {
    const client = new T1ERC7683Client(
        config.rpcUrl,
        config.contractAddress,
        contractAbi.abi as any,
        privateKey,
        config.chain
    );

    const monitoredTokens = [
        {token: config.weth, decimals: 18, symbol: "WETH"},
        {token: config.usdc, decimals: 6, symbol: "USDC"},
    ];

    const monitor = new ThresholdMonitor(client, monitoredTokens, thresholdUsd);

    console.log(`[${config.chain.name}] Starting ThresholdMonitor with threshold=${thresholdUsd} USD, interval=${pollIntervalMs}ms`);

    while (true) {
        try {
            await monitor.pauseIfAboveThreshold();
        } catch (err) {
            console.error(`[${config.chain.name}] Error during monitor check:`, err);
        }
        await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }
}

async function main() {
    const pauserPrivateKey = process.env.PAUSER_PRIVATE_KEY as `0x${string}`;
    const thresholdUsd = Number(process.env.USD_THRESHOLD);
    const pollIntervalMs = Number(process.env.POLL_INTERVAL_MS);

    const networks: NetworkConfig[] = [
        {
            chain: base,
            rpcUrl: process.env.BASE_RPC_URL as string,
            contractAddress: process.env.BASE_T1ERC7683_CONTRACT_ADDRESS as `0x${string}`,
            weth: process.env.BASE_WETH_ADDRESS as `0x${string}`,
            usdc: process.env.BASE_USDC_ADDRESS as `0x${string}`,
        },
        {
            chain: arbitrum,
            rpcUrl: process.env.ARB_RPC_URL as string,
            contractAddress: process.env.ARB_T1ERC7683_CONTRACT_ADDRESS as `0x${string}`,
            weth: process.env.ARB_WETH_ADDRESS as `0x${string}`,
            usdc: process.env.ARB_USDC_ADDRESS as `0x${string}`,
        },
    ];

    networks.forEach((network) => {
        startMonitor(network, pauserPrivateKey, thresholdUsd, pollIntervalMs);
    });
}

main().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
});
