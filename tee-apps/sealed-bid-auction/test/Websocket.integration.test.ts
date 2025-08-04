import {afterAll, beforeAll, beforeEach, describe, it, expect} from "@jest/globals";

import {SealedBidAuctionApiServer} from "../src/api/SealedBidAuctionApiServer.ts";
import {PRICE_LIST_WITH_GAP_IN_RANGES, USERNAME, PRICE_LIST_WITH_TWO_ITEMS, PRIVATE_KEY, SOLVER_ADDRESS} from "./constants.ts";
import {signMessage} from "viem/accounts";

const wsPort = 3080;
const httpServer = new SealedBidAuctionApiServer();
let socketClosed = true;
let socket: WebSocket;
let socketMessage: string | null;

beforeAll(async () => {
    await httpServer.start(wsPort, false);

    const nonceRes = await fetch(`http://localhost:${wsPort}/api/currentNonce?username=${USERNAME}`);
    const { nonce } = await nonceRes.json();
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

        expect(socketMessage).toBe(`Prices updated: 2 entries for solver ${USERNAME}`);
    });

    it("Should not add Price List with gap in ranges", async () => {
        socket.send(JSON.stringify(PRICE_LIST_WITH_GAP_IN_RANGES));

        while (!socketMessage) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }

        expect(socketMessage).toBe(`Error when updating price: There is a gap between max of range [0] and min of range [1]`);
    });
});
