import type {PriceListItem} from "../core/types.ts";
import {serialize} from "../utils/WinstonLogger.ts";

export class SolverWebSocketClient {

    private socket: WebSocket | null;

    constructor(private readonly hostName: string = 'localhost', private readonly serverPort: number) {
        this.socket = null;
    }

    public async start(username: string, socketResponseConsumer: (sockerResponse: string) => void) {
        this.socket = new WebSocket(`ws://${this.hostName}:${this.serverPort}/`, {
            headers: {
                Authorization: username
            }
        });
        this.socket.onmessage = (event) => {
            socketResponseConsumer(event.data);
        };

        await this.waitForSocketState(WebSocket.OPEN);
    }

    public async stop() {
        if (this.socket) {
            this.socket.close();

            await this.waitForSocketState(WebSocket.CLOSED);

            this.socket = null;
        }
    }

    public sendPrices(message: PriceListItem[]) {
        if (!this.socket) {
            throw Error("Socket is closed");
        }

        this.socket.send(serialize(message));
    }

    private async waitForSocketState(state: 0 | 1 | 2 | 3, timeoutMs: number = 100) {
        if (!this.socket) {
            throw Error("Socket is closed");
        }

        while (this.socket.readyState !== state) {
            await new Promise((resolve) => setTimeout(resolve, timeoutMs));
        }
    }
}