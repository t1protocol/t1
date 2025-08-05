import * as dotenv from "dotenv";

dotenv.config();

import {AuctionApiServer} from "./src/api/AuctionApiServer.ts";
import {ViemIntentObserver} from "./src/blockchain/ViemIntentObserver.ts";
import {SolverPriceBook} from "./src/core/SolverPriceBook.ts";
import {AuctionService} from "./src/core/AuctionService.ts";
import {arbitrumSepolia, baseSepolia} from "viem/chains";

const solverPriceBook = new SolverPriceBook();
const auctionService = new AuctionService(solverPriceBook);

const httpServer = new AuctionApiServer();
const arbitrumSepoliaIntentObserver = new ViemIntentObserver(
    process.env.ARBITRUM_SEPOLIA_RPC as string,
    arbitrumSepolia,
    Number(process.env.ARBITRUM_SEPOLIA_POLLING_INTERVAL_MS as string),
    process.env.ARBITRUM_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    auctionService,
    httpServer
);
const baseSepoliaIntentObserver = new ViemIntentObserver(
    process.env.BASE_SEPOLIA_RPC as string,
    baseSepolia,
    Number(process.env.BASE_SEPOLIA_POLLING_INTERVAL_MS as string),
    process.env.BASE_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    auctionService,
    httpServer
);

async function main() {
    await httpServer.start(Number(process.env.SERVER_PORT as string), true);
    arbitrumSepoliaIntentObserver.start();
    baseSepoliaIntentObserver.start();
}

async function stopAll() {
    await httpServer.stop();
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
