import * as dotenv from "dotenv";

dotenv.config();

import {SealedBidAuctionApiServer} from "./src/api/SealedBidAuctionApiServer.ts";
import {ArbitrumSepoliaIntentObserver} from "./src/blockchain/ArbitrumSepoliaIntentObserver.ts";
import {SolverPriceBook} from "./src/core/SolverPriceBook.ts";
import {AuctionService} from "./src/core/AuctionService.ts";

const httpServer = new SealedBidAuctionApiServer();
const solverPriceBook = new SolverPriceBook();
const auctionService = new AuctionService(solverPriceBook);
const arbitrumIntentObserver = new ArbitrumSepoliaIntentObserver(
    process.env.ARBITRUM_SEPOLIA_RPC as string,
    Number(process.env.ARBITRUM_SEPOLIA_POLLING_INTERVAL_MS as string),
    process.env.ARBITRUM_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    auctionService,
    httpServer
);

async function main() {
    await httpServer.start(Number(process.env.SERVER_PORT as string), true);
    arbitrumIntentObserver.start();
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
