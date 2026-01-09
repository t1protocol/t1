import {afterAll, beforeAll, beforeEach, describe, it, expect} from "@jest/globals";

import {AuctionApiServer} from "../src/api/AuctionApiServer.ts";
import {PRICE_LIST_WITH_GAP_IN_RANGES, USERNAME, PRICE_LIST_WITH_TWO_ITEMS, PRIVATE_KEY, SOLVER_ADDRESS} from "./constants.ts";
import {SolverPriceBook} from "../src/core/SolverPriceBook.ts";
import {AuctionService} from "../src/core/AuctionService.ts";
import {signMessage} from "viem/accounts";
import { AuthService } from "../src/core/AuthService.ts";

const wsPort = 3080;
const authService = new AuthService();
const solverPriceBook  = new SolverPriceBook(authService, 600);
const httpServer = new AuctionApiServer(solverPriceBook, authService, new AuctionService(solverPriceBook));
let socketClosed = true;
let socket: WebSocket;
let socketMessage: string | null;

beforeAll(async () => {
    await httpServer.start(wsPort, false);

    const nonceRes1 = await fetch(`http://localhost:${wsPort}/api/currentNonce?username=${USERNAME}`);
    const { nonce } = await nonceRes1.json();
    const nonceRes2 = await fetch(`http://localhost:${wsPort}/api/currentNonce?username=${USERNAME}`);
    const { nonce: nonceAgain } = await nonceRes2.json();
    expect(nonceAgain).toBe(nonce);
    const blobString = JSON.stringify({ username: USERNAME, nonce });
    const signature = await signMessage({ message: blobString, privateKey: PRIVATE_KEY as `0x${string}` });

    socket = new WebSocket(`ws://localhost:${wsPort}/`, {
        headers: {
            "X-Auth-Blob": blobString,
            "X-Auth-Signature": signature
        }
    });
    socket.onopen = () => {
        socketClosed = false;
    };
    socket.onclose = () => {
        socketClosed = true;
    };
    socket.onmessage = (event) => {
        socketMessage = event.data;
    };

    while (socketClosed) {
        await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const nonceRes3 = await fetch(`http://localhost:${wsPort}/api/currentNonce?username=${USERNAME}`);
    const { nonce: rotated } = await nonceRes3.json();
    expect(rotated).not.toBe(nonce);
});

afterAll(async () => {
    socket.close();

    // await 1 sec because otherwise we attempt to continue before socket is closed, even if socket claims that it's closed...
    await new Promise((resolve) => setTimeout(resolve, 1000));

    expect(socketClosed);

    await httpServer.stop();
});

beforeEach(() => {
    socketMessage = null;
})

describe("Websocket Integration Test", () => {
    it("Should add Price List", async () => {
        socket.send(JSON.stringify(PRICE_LIST_WITH_TWO_ITEMS));

        while (!socketMessage) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }

        expect(socketMessage).toBe(`Prices updated: 2 entries for solver ${SOLVER_ADDRESS.toLowerCase()}`);

        const priceBook = (httpServer as any)["solverPriceBook"];
        const prices = (priceBook as any)["prices"] as Map<string, any>;
        const entry = prices.get(SOLVER_ADDRESS.toLowerCase());
        expect(entry).toBeDefined();
        entry.priceList.forEach((item: any) => {
            expect(item.settlementReceiverAddress).toBe(SOLVER_ADDRESS.toLowerCase());
        });
    });

    it("Should not add Price List with gap in ranges", async () => {
        socket.send(JSON.stringify(PRICE_LIST_WITH_GAP_IN_RANGES));

        while (!socketMessage) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }

        expect(socketMessage).toBe(`Error when updating price: There is a gap between max of range [0] and min of range [1]`);
    });

    it("Should reject parallel connections with the same nonce", async () => {
        const nonceRes = await fetch(`http://localhost:${wsPort}/api/currentNonce?username=${USERNAME}`);
        const { nonce } = await nonceRes.json();
        const blobString = JSON.stringify({ username: USERNAME, nonce });
        const signature = await signMessage({ message: blobString, privateKey: PRIVATE_KEY as `0x${string}` });

        const headers = { "X-Auth-Blob": blobString, "X-Auth-Signature": signature };
        const ws1 = new WebSocket(`ws://localhost:${wsPort}/`, { headers });
        const ws2 = new WebSocket(`ws://localhost:${wsPort}/`, { headers });

        const wait = (ws: WebSocket) =>
            new Promise<boolean>((resolve) => {
                ws.onopen = () => resolve(true);
                ws.onerror = () => resolve(false);
                ws.onclose = () => resolve(false);
            });

        const [r1, r2] = await Promise.all([wait(ws1), wait(ws2)]);
        expect(Number(r1) + Number(r2)).toBe(1);

        ws1.close();
        ws2.close();
    });
});
