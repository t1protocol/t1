import type {Server} from "bun";

import {SealedBidAuctionController} from "./SealedBidAuctionController.ts";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import {SolverPriceBook} from "../core/SolverPriceBook.ts";
import {AuctionService} from "../core/AuctionService.ts";

type AuthData = {
    username: string;
};

export class SealedBidAuctionApiServer {
    private logger = new WinstonLogger(SealedBidAuctionApiServer.name);

    private readonly solverPriceBook;
    private readonly auctionController;

    private server: Server | null = null;

    public constructor() {
        this.solverPriceBook = new SolverPriceBook();
        this.auctionController = new SealedBidAuctionController(new AuctionService(this.solverPriceBook));
    }

    public async start(port: number, tls: boolean) {
        if (this.server) {
            this.logger.warn("API server is already running");
            return;
        }

        const solverPriceBook = this.solverPriceBook;

        // @ts-ignore
        this.server = Bun.serve<AuthData>({
            port,
            tls: tls ? {
                key: Bun.file("./key.pem"),
                cert: Bun.file("./cert.pem"),
            } : {},
            routes: {
                "/healthcheck": new Response("OK"),
                "/api/preauction": req => this.auctionController.preauction(req),
            },
            fetch(req, server) {
                const success = server.upgrade(req, {
                    data: {
                        username: req.headers.get("Authorization")
                    }
                });
                if (success) {
                    // Bun automatically returns a 101 Switching Protocols
                    // if the upgrade succeeds
                    return undefined;
                }

                return new Response("OK");
            },
            websocket: {
                open(ws) {
                    ws.subscribe('intent-auction');
                    console.log(`Client ${ws.data.username} connected`);
                    ws.send("Welcome!");
                },
                message(ws, message) {
                    try {
                        const addedCount = solverPriceBook.updatePrice(ws.data.username, message.toString());
                        ws.send(`I updated [${addedCount}] prices for [${ws.data.username}]!`);
                    } catch (e: any) {
                        console.error(`Error when updating price: ${e}`);
                        ws.send(`Error when updating price: ${e}`);
                    }
                },
                close(ws, _code, _reason) {
                    ws.unsubscribe('intent-auction');
                    console.log(`Client ${ws.data.username} disconnected`);
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

    public publishAuctionResult(msg: string) {
        this.server?.publish('intent-auction', msg);
    }
}