import {SealedBidAuctionController} from "./SealedBidAuctionController.ts";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import type {Server} from "bun";

export class SealedBidAuctionApiServer {

    private logger: WinstonLogger = new WinstonLogger(SealedBidAuctionApiServer.name);

    private server: Server | null = null;

    public async start(port: number) {
        if (this.server) {
            this.logger.warn("HTTP API server is already running");
            return;
        }

        const auctionController = new SealedBidAuctionController();

        this.server = Bun.serve({
            port,
            routes: {
                "/healthcheck": new Response("OK"),
                "/api/auction": req => auctionController.auction(req),
            },
        });

        this.logger.info(`API server started on port ${port}`);
    }

    public async stop() {
        if (this.server) {
            this.logger.info("Stopping API server...")
            await this.server.stop();
            this.server = null;
            this.logger.info("API server stopped");
        }
    }
}