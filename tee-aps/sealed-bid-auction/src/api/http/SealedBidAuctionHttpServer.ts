import express from "express";
import cors from "cors";
import {Server} from "http";

import {SealedBidAuctionController} from "./SealedBidAuctionController.ts";
import {WinstonLogger} from "../../utils/WinstonLogger.ts";

export class SealedBidAuctionHttpServer {

    private logger: WinstonLogger = new WinstonLogger(SealedBidAuctionHttpServer.name);

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
        const auctionController = new SealedBidAuctionController();

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