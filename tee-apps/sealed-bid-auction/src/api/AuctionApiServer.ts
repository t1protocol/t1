import type {Server} from "bun";

import {AuctionController} from "./AuctionController.ts";
import {serialize, WinstonLogger} from "../utils/WinstonLogger.ts";
import {SolverPriceBook} from "../core/SolverPriceBook.ts";
import {AuctionService, type Price} from "../core/AuctionService.ts";
import type {AuctionResult} from "./types.ts";
import type {OrderData} from "../blockchain/types.ts";
import type {ViemAuctionCommiter} from "../blockchain/ViemAuctionCommiter.ts";

type AuthData = {
    username: string;
};

export class AuctionApiServer {
    private logger = new WinstonLogger(AuctionApiServer.name);

    private readonly auctionController;

    private server: Server | null = null;

    public constructor(
        private readonly solverPriceBook: SolverPriceBook,
        private readonly auctionCommiter: ViemAuctionCommiter,
        auctionService: AuctionService
    ) {
        this.auctionController = new AuctionController(auctionService);
    }

    public async start(port: number, tls: boolean) {
        if (this.server) {
            this.logger.warn("API server is already running");
            return;
        }
        const solverPriceBook = this.solverPriceBook;
        const websocketLogger = new WinstonLogger(`${AuctionApiServer.name}-websocket`);

        // @ts-ignore
        this.server = Bun.serve<AuthData>({
            port,
            tls: tls ? {
                key: Bun.file("./key.pem"),
                cert: Bun.file("./cert.pem"),
            } : {},
            routes: {
                "/healthcheck": new Response("OK"),
                "/api/preauction": {
                    GET: _req => this.auctionController.wrongMethodError(),
                    POST: async (req) => await this.auctionController.preauction(req)
                }
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
                    websocketLogger.info(`Client ${ws.data.username} connected`);
                    ws.send("Welcome!");
                },
                message(ws, message) {
                    try {
                        const addedCount = solverPriceBook.updatePrice(ws.data.username, message.toString());
                        ws.send(`I updated [${addedCount}] prices for [${ws.data.username}]!`);
                    } catch (e: any) {
                        websocketLogger.error(`Error when updating price: ${e}`);
                        ws.send(`Error when updating price: ${e}`);
                    }
                },
                close(ws, _code, _reason) {
                    ws.unsubscribe('intent-auction');
                    websocketLogger.info(`Client ${ws.data.username} disconnected`);
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

    public async publishAuctionResult(price: Price, orderId: string, orderData: OrderData, chainId: number) {
        const result: AuctionResult = {
            settlementReceiverAddress: price.settlementReceiverAddress,
            amountOut: price.amountOut,
            orderId,
            orderData
        }

        this.server?.publish('intent-auction', `[${result.settlementReceiverAddress}] won auction on chain [${chainId}] : ${serialize(result)}`);
        this.logger.info(`I sent commitWinnerBid in txHash=[${await this.auctionCommiter.commitWinnerBid(result)}]`);
    }
}