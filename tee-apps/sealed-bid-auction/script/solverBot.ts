import * as dotenv from "dotenv";

dotenv.config();

import {SolverWebSocketClient} from "../src/bot/SolverWebSocketClient.ts";
import {ATTRACTIVE_ARBITRUM_PRICE, ATTRACTIVE_BASE_PRICE} from "../src/bot/samplePriceLists.ts";
import {ViemBlockchainClient} from "../src/blockchain/ViemBlockchainClient.ts";
import {arbitrumSepolia, baseSepolia} from "viem/chains";
import {ViemT1ERC7683Client} from "../src/blockchain/ViemT1ERC7683Client.ts";

const WS_URL = process.env.WS_URL as string;
// const NINE_MINUTES_IN_MS = 540_000;
const TWO_SECONDS = 2_000;

const arbitrumClient = new ViemBlockchainClient(
    process.env.ARBITRUM_SEPOLIA_RPC as string,
    arbitrumSepolia,
    Number(process.env.ARBITRUM_SEPOLIA_POLLING_INTERVAL_MS as string),
    process.env.ARBITRUM_SIGNER_PRIVATE_KEY as `0x${string}`
);
const baseClient = new ViemBlockchainClient(
    process.env.BASE_SEPOLIA_RPC as string,
    baseSepolia,
    Number(process.env.BASE_SEPOLIA_POLLING_INTERVAL_MS as string),
    process.env.BASE_SIGNER_PRIVATE_KEY as `0x${string}`
);
const arbitrumSepoliaT1ERC7683Client = new ViemT1ERC7683Client(
    process.env.ARBITRUM_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    arbitrumClient
);
const baseSepoliaT1ERC7683Client = new ViemT1ERC7683Client(
    process.env.BASE_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    baseClient
);

const tokkaSolver = new SolverWebSocketClient(
    WS_URL,
    arbitrumSepoliaT1ERC7683Client,
    baseSepoliaT1ERC7683Client,
    ATTRACTIVE_ARBITRUM_PRICE
);
const ecoSolver = new SolverWebSocketClient(
    WS_URL,
    arbitrumSepoliaT1ERC7683Client,
    baseSepoliaT1ERC7683Client,
    ATTRACTIVE_BASE_PRICE
);

async function main() {
    await tokkaSolver.start('tokka', console.log);
    await ecoSolver.start('eco', console.log);

    while (true) {
        tokkaSolver.sendPrices();
        ecoSolver.sendPrices();
        await new Promise((resolve) => setTimeout(resolve, TWO_SECONDS));
    }
}

async function stopAll() {
    await tokkaSolver.stop();
    await ecoSolver.stop();
}

main()
    .then()
    .catch(async (error) => {
        await stopAll();
        console.error("", error);
        process.exit(1);
    });

process.on("SIGINT", async () => {
    await stopAll();
    process.exit(0);
});

process.on("SIGTERM", async () => {
    await stopAll();
    process.exit(0);
});