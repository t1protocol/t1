import {SealedBidAuctionHttpServer} from "./src/api/http/SealedBidAuctionHttpServer.ts";
import {SealedBidPriceWebsocketServer} from "./src/api/ws/SealedBidPriceWebsocketServer.ts";

const httpServer = new SealedBidAuctionHttpServer();
const wsServer = new SealedBidPriceWebsocketServer();

async function main() {
    await httpServer.start(3010);
    await wsServer.start(3011);
}

main()
    .then()
    .catch((error) => {
        httpServer.stop();
        wsServer.stop();
        console.error("", error);
        process.exit(1);
    });

process.on("SIGINT", () => {
    httpServer.stop();
    wsServer.stop();
    process.exit(0);
});

process.on("SIGTERM", () => {
    httpServer.stop();
    wsServer.stop();
    process.exit(0);
});
