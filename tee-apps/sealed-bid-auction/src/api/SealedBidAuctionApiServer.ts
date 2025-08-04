import type {Server} from "bun";
import crypto from "node:crypto";
import {hashMessage, recoverAddress} from "viem";

import {SealedBidAuctionController} from "./SealedBidAuctionController.ts";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import {SolverPriceBook} from "../core/SolverPriceBook.ts";
import {AuctionService, type Price} from "../core/AuctionService.ts";
import type {AuctionResult, AuthBlob} from "./types.ts";
import type {OrderData} from "../blockchain/types.ts";

type AuthData = {
    username: string;
    solverAddress: string;
};

export class SealedBidAuctionApiServer {
    private logger = new WinstonLogger(SealedBidAuctionApiServer.name);

    private readonly solverPriceBook;
    private readonly auctionController;

    private server: Server | null = null;
    private readonly nonces: Map<string, string> = new Map();
    private readonly authenticatedSolvers: Set<string> = new Set();

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
        const authenticatedSolvers = this.authenticatedSolvers;

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

                const blobHeader = req.headers.get("X-Auth-Blob");
                const sig = req.headers.get("X-Auth-Signature");
                if (!blobHeader || !sig) {
                    return new Response("Unauthorized", { status: 401 });
                }

                let authBlob: AuthBlob;
                try {
                    authBlob = JSON.parse(blobHeader) as AuthBlob;
                } catch {
                    return new Response("Unauthorized", { status: 401 });
                }

                const { username, nonce } = authBlob;
                const expectedNonce = username && nonces.get(username);
                if (!username || !nonce || !expectedNonce || nonce !== expectedNonce) {
                    return new Response("Unauthorized", { status: 401 });
                }

                let solverAddress: string;
                try {
                    const hash = hashMessage(blobHeader);
                    solverAddress = await recoverAddress({ hash, signature: sig });
                } catch (err) {
                    console.error("Signature verification failed:", err);
                    return new Response("Unauthorized", { status: 401 });
                }

                solverAddress = solverAddress.toLowerCase();
                console.log(`WebSocket auth success for user "${username}" with address ${solverAddress}`);

                nonces.set(username, crypto.randomUUID());
                authenticatedSolvers.add(solverAddress);

                const success = server.upgrade(req, {
                    data: { username, solverAddress }
                });
                if (success) {
                    return undefined;
                }

                authenticatedSolvers.delete(solverAddress);
                return new Response("WebSocket Upgrade failed", { status: 500 });
            },
            websocket: {
                open: (ws) => {
                    const addr = ws.data.solverAddress;
                    const user = ws.data.username;
                    ws.subscribe('intent-auction');
                    console.log(`✅ Solver connected: ${user} (${addr})`);
                    ws.send("Welcome! Authentication successful.");
                },
                message(ws, message) {
                    try {
                        const addr = ws.data.solverAddress;
                        const user = ws.data.username;
                        const text = message.toString();
                        if (!authenticatedSolvers.has(addr)) {
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
                close: (ws, _code, _reason) => {
                    const addr = ws.data.solverAddress;
                    const user = ws.data.username;
                    ws.unsubscribe('intent-auction');
                    console.log(`🔒 Solver disconnected: ${user} (${addr})`);
                    authenticatedSolvers.delete(addr);
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