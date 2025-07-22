import express from "express";
import cors from "cors";
import {Server} from "http";

import {SealedBidAuctionController} from "./SealedBidAuctionController.ts";
import {WinstonLogger} from "../../utils/WinstonLogger.ts";

export class SealedBidAuctionHttpServer {

    private logger: WinstonLogger = new WinstonLogger(SealedBidAuctionHttpServer.name);

    private server: Server | null = null;

    public async start(port: number) {
        if (this.server) {
            this.logger.warn("HTTP API server is already running");
            return;
        }

        const app = express();
        const router = express.Router();

        // Middleware
        app.use(cors());
        app.use(express.json());

        // Register routes
        const auctionController = new SealedBidAuctionController();

        router.post("/auction",
            (req, res) => auctionController.open(req, res)
        );

        app.use("/api", router);

        this.server = app.listen(port, () => {
            this.logger.info(`HTTP API server started on port ${port}`);
        });
    }

    public stop() {
        if (this.server) {
            this.logger.info("Stopping HTTP API server...")
            this.server.close();
            this.server = null;
            this.logger.info("HTTP API server stopped");
        }
    }
}