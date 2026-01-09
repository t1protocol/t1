import * as dotenv from "dotenv";
import {AuctionApiServer} from "../src/api/AuctionApiServer.ts";
import {ViemIntentObserver} from "../src/blockchain/ViemIntentObserver.ts";
import {SolverPriceBook} from "../src/core/SolverPriceBook.ts";
import {AuctionService} from "../src/core/AuctionService.ts";
import {arbitrum, arbitrumSepolia, base, baseSepolia} from "viem/chains";
import {BlockchainClient} from "../src/blockchain/BlockchainClient.ts";
import { AuthService } from "../src/core/AuthService.ts";

dotenv.config();

const USE_TLS = process.env.USE_TLS as string === "true";
const IS_MAINNET = process.env.IS_MAINNET as string === "true";
const SOLVER_PRICE_TTL_SECONDS = process.env.SOLVER_PRICE_TTL_SECONDS
const TEN_MINUTES_IN_SECONDS = 600;

const BASE_T1_ERC_7683_CONTRACT_ADDRESS = process.env.BASE_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`;
const ARBITRUM_T1_ERC_7683_CONTRACT_ADDRESS = process.env.ARBITRUM_T1_ERC7683_CONTRACT_ADDRESS as `0x${string}`;

const ARBITRUM_WS = (process.env.ARBITRUM_WS) as string;
const BASE_WS = (process.env.BASE_WS) as string;

const authService = new AuthService();
const solverPriceBook = new SolverPriceBook(authService, SOLVER_PRICE_TTL_SECONDS ? Number(SOLVER_PRICE_TTL_SECONDS as string) : TEN_MINUTES_IN_SECONDS);
const auctionService = new AuctionService(solverPriceBook);

const httpServer = new AuctionApiServer(solverPriceBook, authService, auctionService);
const arbitrumClient = new BlockchainClient(
    ARBITRUM_WS,
    IS_MAINNET ? arbitrum : arbitrumSepolia,
    process.env.ARBITRUM_SIGNER_PRIVATE_KEY as `0x${string}`
);
const baseClient = new BlockchainClient(
    BASE_WS,
    IS_MAINNET ? base : baseSepolia,
    process.env.BASE_SIGNER_PRIVATE_KEY as `0x${string}`
);

const fromBlockEnvArbitrum = process.env.INTENT_OBSERVER_FROM_BLOCK_ARBITRUM;
const fromBlockArbitrum = fromBlockEnvArbitrum ? BigInt(fromBlockEnvArbitrum) : null;
const fromBlockEnvBase = process.env.INTENT_OBSERVER_FROM_BLOCK_BASE;
const fromBlockBase = fromBlockEnvBase ? BigInt(fromBlockEnvBase) : null;
const auctionPollingInterval = 500;

const arbitrumSepoliaIntentObserver = new ViemIntentObserver(
    arbitrumClient,
    ARBITRUM_T1_ERC_7683_CONTRACT_ADDRESS,
    auctionService,
    httpServer,
    baseClient.publicClient.chain.id,
    BASE_T1_ERC_7683_CONTRACT_ADDRESS,
    auctionPollingInterval,
    fromBlockArbitrum
);
const baseSepoliaIntentObserver = new ViemIntentObserver(
    baseClient,
    BASE_T1_ERC_7683_CONTRACT_ADDRESS,
    auctionService,
    httpServer,
    arbitrumClient.publicClient.chain.id,
    ARBITRUM_T1_ERC_7683_CONTRACT_ADDRESS,
    auctionPollingInterval,
    fromBlockBase
);

async function main() {
    console.log(`Starting ${IS_MAINNET ? 'mainnet' : 'testnet'} Sealed Bid API server...`);
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
