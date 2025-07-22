import {createServer, Server} from 'http';
import {WebSocketServer} from 'ws';
import {WinstonLogger} from "../../utils/WinstonLogger.ts";


export class SealedBidPriceWebsocketServer {

    private logger: WinstonLogger = new WinstonLogger(SealedBidPriceWebsocketServer.name);

    private server: Server | null = null;

    public async start(port: number) {
        if (this.server) {
            this.logger.warn("WS API server is already running");
            return;
        }

        const tempServer = createServer();
        const wss = new WebSocketServer({noServer: true});

        const thisObject = this;

        wss.on('connection', (ws: any, _request: any, client: any) => {
            ws.on('error', thisObject.logger.error);

            ws.on('message', function message(data: any) {
                thisObject.logger.info(`Received message ${data} from user ${client}`);
            });
        });

        tempServer.on('upgrade', function upgrade(request, socket, head) {
            socket.on('error', thisObject.logger.error);

            thisObject.logger.info('This is where we authenticate client');
            thisObject.authenticate(request, function next(err, client) {
                if (err || !client) {
                    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
                    socket.destroy();
                    return;
                }

                socket.removeListener('error', thisObject.logger.error);

                wss.handleUpgrade(request, socket, head, function done(ws: any) {
                    wss.emit('connection', ws, request, client);
                });
            });
        });

        this.server = tempServer.listen(port, () => {
            this.logger.info(`WS API server started on port ${port}`);
        });
    }

    public stop() {
        if (this.server) {
            this.logger.info("Stopping WS API server...")
            this.server.close();
            this.server = null;
            this.logger.info("WS API server stopped");
        }
    }

    private authenticate(_request: any, _next: (err: any, client: any) => void) {
        throw new Error("Not Implemented");
    }
}