import {afterAll, beforeAll, beforeEach, describe, it, expect} from "@jest/globals";

import {SealedBidAuctionApiServer} from "../src/api/SealedBidAuctionApiServer.ts";
import {PRICE_LIST_WITH_GAP_IN_RANGES, USERNAME, PRICE_LIST_WITH_TWO_ITEMS} from "./constants.ts";

const wsPort = 3080;
const httpServer = new SealedBidAuctionApiServer();
let socketClosed = true;
let socket: WebSocket;
let socketMessage: string | null;

beforeAll(async () => {
    await httpServer.start(wsPort, false);

    socket = new WebSocket(`ws://localhost:${wsPort}/`, {
        headers: {
            Authorization: USERNAME
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
        socket.send(PRICE_LIST_WITH_TWO_ITEMS);

        while (!socketMessage) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }

        expect(socketMessage).toBe(`I updated [2] prices for [${USERNAME}]!`);
    });

    it("Should not add Price List with gap in ranges", async () => {
        socket.send(PRICE_LIST_WITH_GAP_IN_RANGES);

        while (!socketMessage) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }

        expect(socketMessage).toBe(`Error when updating price: Error: There is a gap between max of range [0] and min of range [1]`);
    });
});
