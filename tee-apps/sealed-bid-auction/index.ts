import {SealedBidAuctionApiServer} from "./src/api/SealedBidAuctionApiServer.ts";

const httpServer = new SealedBidAuctionApiServer();

async function main() {
    await httpServer.start(3010);
}

main()
    .then()
    .catch(async (error) => {
        await httpServer.stop();
        console.error("", error);
        process.exit(1);
    });

process.on("SIGINT", async () => {
    await httpServer.stop();
    process.exit(0);
});

process.on("SIGTERM", async () => {
    await httpServer.stop();
    process.exit(0);
});
