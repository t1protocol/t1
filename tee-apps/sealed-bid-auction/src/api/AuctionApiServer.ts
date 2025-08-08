import type {BunRequest, Server} from "bun";
import {hashMessage, recoverAddress} from "viem";

import {AuctionController} from "./AuctionController.ts";
import {serialize, WinstonLogger} from "../utils/WinstonLogger.ts";
import {SolverPriceBook} from "../core/SolverPriceBook.ts";
import {AuctionService, type Price} from "../core/AuctionService.ts";
import type {AuctionResult, AuthBlob} from "./types.ts";
import type {OrderData} from "../blockchain/types.ts";
import type {PriceListItem} from "../core/types.ts";
import {AuthController} from "./AuthController.ts";
import {AuthService} from "../core/AuthService.ts";

type AuthData = {
    username: string;
    solverAddress: string;
};

export class AuctionApiServer {
    private logger = new WinstonLogger(AuctionApiServer.name);

    private readonly auctionController;
    private readonly authController;

    private readonly authService;

    private server: Server | null = null;
    private readonly authenticatedSolvers: Set<string> = new Set();

    public constructor(private readonly solverPriceBook: SolverPriceBook, auctionService: AuctionService) {
        this.auctionController = new AuctionController(auctionService);
        this.authService = new AuthService();
        this.authController = new AuthController(this.authService);
    }

    public async start(port: number, tls: boolean) {
        if (this.server) {
            this.logger.warn("API server is already running");
            return;
        }
        const solverPriceBook = this.solverPriceBook;
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
                "/api/currentNonce": (req: BunRequest) => this.authController.currentNonce(req),
                "/api/preauction": (req: BunRequest) => this.auctionController.preauction(req)
            },
            fetch: async (req, server) => {
                if (req.headers.get("Upgrade")?.toLowerCase() === "websocket") {
                    const blobHeader = req.headers.get("X-Auth-Blob");
                    const sig = req.headers.get("X-Auth-Signature") as `0x${string}`;
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
                    if (!username || !nonce) {
                        return new Response("Unauthorized", { status: 401 });
                    }
                    const key = username.toLowerCase();

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

                    if (!this.authService.consumeNonce(key, nonce)) {
                        return new Response("Unauthorized", { status: 401 });
                    }
                    authenticatedSolvers.add(solverAddress);

                    const success = server.upgrade(req, {
                        data: { username, solverAddress }
                    });
                    if (success) {
                        return undefined;
                    }

                    authenticatedSolvers.delete(solverAddress);
                    return new Response("WebSocket Upgrade failed", { status: 500 });
                }

                return new Response("Not Found", { status: 404 });
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
                        const addr = ws.data.solverAddress as `0x${string}`;
                        if (!authenticatedSolvers.has(addr)) {
                            ws.send('Error: not authenticated');
                            return;
                        }
                        const text = message.toString();
                        const priceData: PriceListItem[] = JSON.parse(text);
                        if (!Array.isArray(priceData)) {
                            throw new Error("Invalid price list format (expected array)");
                        }
                        for (const item of priceData) {
                            item.settlementReceiverAddress = addr;
                        }
                        const addedCount = solverPriceBook.updatePrice(addr, JSON.stringify(priceData));
                        ws.send(`Prices updated: ${addedCount} entries for solver ${addr}`);
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

        this.server?.publish('intent-auction', `[${result.settlementReceiverAddress}] won auction on chain [${chainId}] : ${serialize(result)}`);
    }
}