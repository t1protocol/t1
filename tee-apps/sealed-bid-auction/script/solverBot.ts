import * as dotenv from "dotenv";

dotenv.config();

import {SolverWebSocketClient} from "../src/bot/SolverWebSocketClient.ts";
import {ATTRACTIVE_ARBITRUM_PRICE, ATTRACTIVE_BASE_PRICE} from "../src/bot/samplePriceLists.ts";
import {privateKeyToAccount} from "viem/accounts";

const TOKKA_SOLVER_BOT_PRIVATE_KEY = process.env.TOKKA_SOLVER_BOT_PRIVATE_KEY as `0x${string}`;
const ECO_SOLVER_BOT_PRIVATE_KEY = process.env.ECO_SOLVER_BOT_PRIVATE_KEY as `0x${string}`;
const NEXT_NONCE_URL = process.env.NEXT_NONCE_URL as string;
const WS_URL = process.env.WS_URL as string;
// const NINE_MINUTES_IN_MS = 540_000;
const TWO_SECONDS = 2_000;

const tokkaSolver = new SolverWebSocketClient(WS_URL);
const ecoSolver = new SolverWebSocketClient(WS_URL);

async function main() {
    const tokkaNonce = await getNextNonce('tokka');
    const tokkaBlob = { username: "tokka", nonce: tokkaNonce };
    const tokkaSig = await signMessage(JSON.stringify(tokkaBlob), TOKKA_SOLVER_BOT_PRIVATE_KEY);
    
    const ecoNonce = await getNextNonce('eco');
    const ecoBlob = { username: "eco", nonce: ecoNonce };
    const ecoSig = await signMessage(JSON.stringify(ecoBlob), ECO_SOLVER_BOT_PRIVATE_KEY);

    await tokkaSolver.start('tokka', JSON.stringify(tokkaBlob), tokkaSig, console.log);
    await ecoSolver.start('eco', JSON.stringify(ecoBlob), ecoSig, console.log);

    while (true) {
        tokkaSolver.sendPrices(ATTRACTIVE_ARBITRUM_PRICE);
        ecoSolver.sendPrices(ATTRACTIVE_BASE_PRICE);
        await new Promise((resolve) => setTimeout(resolve, TWO_SECONDS));
    }
}

async function getNextNonce(username: string) {
    const response = await fetch(`${NEXT_NONCE_URL}?username=${username}`, {
        method: "GET",
        headers: { "Content-Type": "application/json" },
    });
    console.log(JSON.stringify(response));

    const r  = await response.json();
    const responseBody  = r as { nonce: string };

    return responseBody.nonce;
}

async function signMessage(message: string, privateKey: `0x${string}`): Promise<`0x${string}`> {
    const account = privateKeyToAccount(privateKey);

    return await account.signMessage({
        message
    })
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