import type {PriceListItem} from "../core/types.ts";
import {serialize, WinstonLogger} from "../utils/WinstonLogger.ts";

export class SolverWebSocketClient {
    private logger!: WinstonLogger;

    private socket: WebSocket | null;

    constructor(private readonly serverUrl: string) {
        this.socket = null;
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

    public sendPrices(message: PriceListItem[]) {
        if (!this.socket) {
            throw Error("Socket is closed");
        }

        this.socket.send(serialize(message));

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
}