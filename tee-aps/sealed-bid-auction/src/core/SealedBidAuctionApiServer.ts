import express from "express";
import cors from "cors";
import {Server} from "http";

import {AuctionController} from "../api/controller/AuctionController.ts";
import {WinstonLogger} from "./utils/WinstonLogger.ts";

export class SealedBidAuctionApiServer {

    private logger: WinstonLogger = new WinstonLogger(SealedBidAuctionApiServer.name);

    private apiServer: Server | null = null;

    async start(port: number) {
        if (this.apiServer) {
            this.logger.warn("API server is already running");
            return;
        }

        const app = express();
        const router = express.Router();

        // Middleware
        app.use(cors());
        app.use(express.json());

        // Register routes
        const auctionController = new AuctionController();

        router.post("/auction",
            (req, res) => auctionController.open(req, res)
        );

        app.use("/api", router);

        this.apiServer = app.listen(port, () => {
            this.logger.info(`API server started on port ${port}`);
        });
    }

    public stop() {
        if (this.apiServer) {
            this.logger.info("Stopping API server...")
            this.apiServer.close();
            this.apiServer = null;
            this.logger.info("API server stopped");
        }
    }
}