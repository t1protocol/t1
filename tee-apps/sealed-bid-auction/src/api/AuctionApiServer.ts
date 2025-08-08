import type {BunRequest, Server} from "bun";

import {AuctionController} from "./AuctionController.ts";
import {serialize, WinstonLogger} from "../utils/WinstonLogger.ts";
import {SolverPriceBook} from "../core/SolverPriceBook.ts";
import {AuctionService, type Price} from "../core/AuctionService.ts";
import type {AuctionResult} from "./types.ts";
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
        const authService = this.authService;

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
                    const authAttempt = this.authController.validateAuthAttempt(blobHeader, sig);
                    if (!authAttempt) {
                        return new Response(
                            `Incorrect login data; blobheader=[${blobHeader}] or sig=[${sig}]`,
                            { status: 400 }
                        );
                    }
                    const authenticatedUser = await this.authService.login(authAttempt);

                    if (!authenticatedUser) {
                        return new Response("Unauthorized", { status: 401 });
                    }

                    const success = server.upgrade(req, {
                        data: { username: authenticatedUser.username, solverAddress: authenticatedUser.solverAddress }
                    });
                    if (success) {
                        return undefined;
                    }

                    this.authService.logout(authenticatedUser.solverAddress);

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
                        if (!authService.isLoggedIn(addr)) {
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
                    authService.logout(addr);
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