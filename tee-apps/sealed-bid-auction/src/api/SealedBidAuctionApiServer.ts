import {SealedBidAuctionController} from "./SealedBidAuctionController.ts";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import type {Server} from "bun";

type AuthData = {
    token: string;
};

export class SealedBidAuctionApiServer {

    private logger: WinstonLogger = new WinstonLogger(SealedBidAuctionApiServer.name);

    private server: Server | null = null;

    public async start(port: number) {
        if (this.server) {
            this.logger.warn("API server is already running");
            return;
        }

        const auctionController = new SealedBidAuctionController();
        const infoLogger = this.logger.info;

        // @ts-ignore
        this.server = Bun.serve<AuthData>({
            port,
            routes: {
                "/healthcheck": new Response("OK"),
                "/api/auction": req => auctionController.auction(req),
            },
            fetch(req, server) {
                const success = server.upgrade(req, {
                    data: {
                        token: req.headers.get("Authorization")
                    }
                });
                if (success) {
                    // Bun automatically returns a 101 Switching Protocols
                    // if the upgrade succeeds
                    return undefined;
                }

                return new Response("Hello WebSocket!");
            },
            websocket: {
                async message(ws, message) {
                    infoLogger(`Received ${message}`);
                    infoLogger(`Auth token [${ws.data.token}]`);
                    // send back a message
                    ws.send(`You said: ${message}`);
                },
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