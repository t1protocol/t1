import * as dotenv from "dotenv";

dotenv.config();

import {AuctionApiServer} from "../src/api/AuctionApiServer.ts";
import {ViemIntentObserver} from "../src/blockchain/ViemIntentObserver.ts";
import {SolverPriceBook} from "../src/core/SolverPriceBook.ts";
import {AuctionService} from "../src/core/AuctionService.ts";
import {arbitrumSepolia, baseSepolia} from "viem/chains";
import {BlockchainClient} from "../src/blockchain/BlockchainClient.ts";
import {ViemAuctionCommiter} from "../src/blockchain/ViemAuctionCommiter.ts";

const USE_TLS = process.env.USE_TLS as string === "true";
const SOLVER_PRICE_TTL_SECONDS = process.env.SOLVER_PRICE_TTL_SECONDS as string;
const TEN_MINUTES_IN_SECONDS = 600;

const solverPriceBook = new SolverPriceBook(SOLVER_PRICE_TTL_SECONDS ? Number(SOLVER_PRICE_TTL_SECONDS) : TEN_MINUTES_IN_SECONDS);
const auctionService = new AuctionService(solverPriceBook);

const httpServer = new AuctionApiServer(solverPriceBook, auctionService);
const arbitrumClient = new BlockchainClient(
    process.env.ARBITRUM_SEPOLIA_RPC as string,
    arbitrumSepolia,
    Number(process.env.ARBITRUM_SEPOLIA_POLLING_INTERVAL_MS as string),
    process.env.ARBITRUM_SIGNER_PRIVATE_KEY as `0x${string}`
);
const baseClient = new BlockchainClient(
    process.env.BASE_SEPOLIA_RPC as string,
    baseSepolia,
    Number(process.env.BASE_SEPOLIA_POLLING_INTERVAL_MS as string),
    process.env.BASE_SIGNER_PRIVATE_KEY as `0x${string}`
);
const arbitrumSepoliaAuctionCommiter = new ViemAuctionCommiter(
    process.env.ARBITRUM_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    arbitrumClient
);
const baseSepoliaAuctionCommiter = new ViemAuctionCommiter(
    process.env.BASE_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    baseClient
);
const arbitrumSepoliaIntentObserver = new ViemIntentObserver(
    arbitrumClient,
    arbitrumSepoliaAuctionCommiter,
    process.env.ARBITRUM_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    auctionService,
    httpServer
);
const baseSepoliaIntentObserver = new ViemIntentObserver(
    baseClient,
    baseSepoliaAuctionCommiter,
    process.env.BASE_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`,
    auctionService,
    httpServer
);

async function main() {
    await httpServer.start(Number(process.env.SERVER_PORT as string), USE_TLS);
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
