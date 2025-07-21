import {SealedBidAuctionApiServer} from "./src/core/SealedBidAuctionApiServer.ts";

const apiServer = new SealedBidAuctionApiServer();

async function main() {
    await apiServer.start(3010);
}

main()
    .then()
    .catch((error) => {
        apiServer.stop();
        console.error("", error);
        process.exit(1);
    });

process.on("SIGINT", () => {
    apiServer.stop();
    process.exit(0);
});

process.on("SIGTERM", () => {
    apiServer.stop();
    process.exit(0);
});
