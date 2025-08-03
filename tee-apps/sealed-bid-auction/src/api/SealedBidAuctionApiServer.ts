import type {Server} from "bun";
import crypto from "node:crypto";
import {hashMessage, recoverAddress} from "viem";

import {SealedBidAuctionController} from "./SealedBidAuctionController.ts";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import {SolverPriceBook} from "../core/SolverPriceBook.ts";
import {AuctionService, type Price} from "../core/AuctionService.ts";
import type {AuctionResult} from "./types.ts";
import type {OrderData} from "../blockchain/types.ts";

type AuthData = {
    username: string;
    address: string;
};

export class SealedBidAuctionApiServer {
    private logger = new WinstonLogger(SealedBidAuctionApiServer.name);

    private readonly solverPriceBook;
    private readonly auctionController;

    private server: Server | null = null;
    private readonly nonces: Map<string, string> = new Map();

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
        const nonces = this.nonces;

        // @ts-ignore
        this.server = Bun.serve<AuthData>({
            port,
            tls: tls ? {
                key: Bun.file("./key.pem"),
                cert: Bun.file("./cert.pem"),
            } : {},
            routes: {
                "/healthcheck": new Response("OK"),
                "/api/currentNonce": req => {
                    const username = new URL(req.url).searchParams.get("username");
                    if (!username) {
                        return new Response("Missing username", { status: 400 });
                    }
                    const nonce = crypto.randomUUID();
                    nonces.set(username, nonce);
                    const body = JSON.stringify({ nonce });
                    return new Response(body, { status: 200, headers: { "Content-Type": "application/json" } });
                },
                "/api/preauction": req => this.auctionController.preauction(req),
            },
            async fetch(req, server) {
                if (req.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
                    return new Response("OK");
                }

                const username = req.headers.get("X-Auth-Username");
                const nonce = req.headers.get("X-Auth-Nonce");
                const sig = req.headers.get("X-Auth-Signature");
                if (!username || !nonce || !sig) {
                    return new Response("Missing authentication credentials", { status: 401 });
                }

                const expectedNonce = nonces.get(username);
                if (!expectedNonce || nonce !== expectedNonce) {
                    return new Response("Invalid or expired nonce", { status: 401 });
                }

                let recoveredAddress: string;
                try {
                    const message = JSON.stringify({ username, nonce });
                    const hash = hashMessage(message);
                    recoveredAddress = await recoverAddress({ hash, signature: sig });
                } catch (err) {
                    console.error("Signature verification failed:", err);
                    return new Response("Unauthorized (signature verification failed)", { status: 401 });
                }

                recoveredAddress = recoveredAddress.toLowerCase();
                console.log(`WebSocket auth success for user "${username}" with address ${recoveredAddress}`);

                nonces.set(username, crypto.randomUUID());

                const success = server.upgrade(req, {
                    data: { username, address: recoveredAddress }
                });
                if (success) {
                    return undefined;
                }

                return new Response("WebSocket Upgrade failed", { status: 500 });
            },
            websocket: {
                open(ws) {
                    const addr = ws.data.address;
                    const user = ws.data.username;
                    ws.subscribe('intent-auction');
                    console.log(`✅ Solver connected: ${user} (${addr})`);
                    solverPriceBook.authenticateSolver(addr);
                    ws.send("Welcome! Authentication successful.");
                },
                message(ws, message) {
                    try {
                        const addr = ws.data.address;
                        const user = ws.data.username;
                        const text = message.toString();
                        if (!solverPriceBook.isAuthenticated(addr)) {
                            throw new Error(`${addr} not authenticated`);
                        }
                        const priceData = JSON.parse(text);
                        if (!Array.isArray(priceData)) {
                            throw new Error("Invalid price list format (expected array)");
                        }
                        for (const item of priceData) {
                            if (item.settlementReceiverAddress?.toLowerCase() !== addr) {
                                throw new Error(`Solver address mismatch in price update: ${item.settlementReceiverAddress}`);
                            }
                        }
                        const addedCount = solverPriceBook.updatePrice(user, text);
                        ws.send(`Prices updated: ${addedCount} entries for solver ${user}`);
                    } catch (e: any) {
                        console.error(`Error processing price update: ${e}`);
                        ws.send(`Error when updating price: ${e.message || e}`);
                    }
                },
                close(ws, _code, _reason) {
                    const addr = ws.data.address;
                    const user = ws.data.username;
                    ws.unsubscribe('intent-auction');
                    console.log(`🔒 Solver disconnected: ${user} (${addr})`);
                    solverPriceBook.logoutSolver(addr);
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

    public publishAuctionResult(price: Price, orderId: string, orderData: OrderData, chainId: number) {
        const result: AuctionResult = {
            settlementReceiverAddress: price.settlementReceiverAddress,
            amountOut: price.amountOut,
            orderId,
            orderData
        }

        this.server?.publish('intent-auction', `[${result.settlementReceiverAddress}] won auction on chain [${chainId}] : ${JSON.stringify(result)}`);
    }
}