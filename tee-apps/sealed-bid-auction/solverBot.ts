import * as dotenv from "dotenv";

dotenv.config();

import {SolverWebSocketClient} from "./src/bot/SolverWebSocketClient.ts";
import {ATTRACTIVE_ARBITRUM_PRICE, ATTRACTIVE_BASE_PRICE} from "./src/bot/samplePriceLists.ts";

const serverPort = Number(process.env.SERVER_PORT as string);
const tokkaSolver = new SolverWebSocketClient(serverPort);
const ecoSolver = new SolverWebSocketClient(serverPort);

async function main() {
    await tokkaSolver.start('tokka', console.log);
    await ecoSolver.start('eco', console.log);

    while (true) {
        tokkaSolver.sendPrices(ATTRACTIVE_ARBITRUM_PRICE);
        ecoSolver.sendPrices(ATTRACTIVE_BASE_PRICE);
        await new Promise((resolve) => setTimeout(resolve, 2000));
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