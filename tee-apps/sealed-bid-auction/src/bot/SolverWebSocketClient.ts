import type {PriceListItem} from "../core/types.ts";
import {serialize, WinstonLogger} from "../utils/WinstonLogger.ts";
import type {AuctionResult} from "../api/types.ts";
import type {ViemT1ERC7683Client} from "../blockchain/ViemT1ERC7683Client.ts";
import {arbitrumSepolia, baseSepolia} from "viem/chains";

export class SolverWebSocketClient {
    private logger!: WinstonLogger;

    private socket: WebSocket | null;

    private readonly winningAuctionRegexp = /^\[0x.*?] won auction on chain \[\d*] : ({.*?})$/;
    private ownArbitrumFillerAddresses: `0x${string}`[];
    private ownBaseFillerAddresses: `0x${string}`[];

    constructor(
        private readonly serverUrl: string,
        private readonly arbitrumT1ERC7683Client: ViemT1ERC7683Client,
        private readonly baseT1ERC7683Client: ViemT1ERC7683Client,
        private readonly priceList: PriceListItem[]
    ) {
        this.socket = null;
        this.ownArbitrumFillerAddresses = priceList.filter(item => item.dstChainId === arbitrumSepolia.id).flatMap(item => item.settlementReceiverAddress);
        this.ownBaseFillerAddresses = priceList.filter(item => item.dstChainId === baseSepolia.id).flatMap(item => item.settlementReceiverAddress);
    }

    public async start(username: string, socketResponseConsumer: (sockerResponse: string) => void) {
        this.logger = new WinstonLogger(`SolverWebSocketClient[${username}]`);

        this.logger.info(`Connecting to server ${this.serverUrl}`);
        this.socket = new WebSocket(this.serverUrl, {
            headers: {
                Authorization: username
            }
        });
        this.socket.onmessage = (event) => {
            socketResponseConsumer(event.data);

            const regexpResult = event.data.match(this.winningAuctionRegexp);
            if (regexpResult) {
                const parsedAuctionResult: AuctionResult = JSON.parse(regexpResult[1]!);

                // if (
                //     this.ownArbitrumFillerAddresses.includes(parsedAuctionResult.settlementReceiverAddress) &&
                //     parsedAuctionResult.orderData.destinationDomain === arbitrumSepolia.id
                // ) {
                //     this.fillIntent(parsedAuctionResult, this.arbitrumT1ERC7683Client, parsedAuctionResult.orderData.destinationDomain);
                // } else if (
                //     this.ownBaseFillerAddresses.includes(parsedAuctionResult.settlementReceiverAddress) &&
                //     parsedAuctionResult.orderData.destinationDomain === baseSepolia.id
                // ) {
                //     this.fillIntent(parsedAuctionResult, this.baseT1ERC7683Client, parsedAuctionResult.orderData.destinationDomain)
                // } else {
                //     throw new Error(`Unexpected dstDomain=[${parsedAuctionResult.orderData.destinationDomain}] !`);
                // }
            }
        };

        await this.waitForSocketState(WebSocket.OPEN);

        this.logger.info(`Connected client ${username}`);
    }

    public async stop() {
        if (this.socket) {
            this.socket.close();

            await this.waitForSocketState(WebSocket.CLOSED);

            this.socket = null;

            this.logger.info("Stopped client");
        }
    }

    public sendPrices() {
        if (!this.socket) {
            throw Error("Socket is closed");
        }

        this.socket.send(serialize(this.priceList));

        this.logger.info("Sent message");
    }

    private async waitForSocketState(state: 0 | 1 | 2 | 3, timeoutMs: number = 100) {
        if (!this.socket) {
            throw Error("Socket is closed");
        }

        while (this.socket.readyState !== state) {
            this.logger.debug(`Waiting for socket state [${state}] but was [${this.socket.readyState}] ...`);
            await new Promise((resolve) => setTimeout(resolve, timeoutMs));
        }
    }

    private async fillIntent(auctionResult: AuctionResult, client: ViemT1ERC7683Client, chainId: number) {
        const txHash = await client.fill(auctionResult);

        this.logger.info(`I filled an intent on chainId=[${chainId}] in a txHash=[${txHash}]`);
    }
}