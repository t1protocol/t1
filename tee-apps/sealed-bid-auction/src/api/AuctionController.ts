import type {BunRequest} from "bun";

import {AuctionService} from "../core/AuctionService.ts";
import type {AuctionRequest} from "./types.ts";
import {serialize} from "../utils/WinstonLogger.ts";

const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
};

export class AuctionController {

    constructor(private readonly auctionService: AuctionService) {}

    public async preauction(req: BunRequest): Promise<Response> {
        try {
            const auctionRequest: AuctionRequest = JSON.parse(await req.text());
            const auctionQuote = this.auctionService.preauction(auctionRequest);

            if (auctionQuote) {
                return new Response(serialize(auctionQuote), {status: 200, headers: CORS_HEADERS});
            } else {
                return new Response(null, {status: 204, headers: CORS_HEADERS});
            }

        } catch (e: any) {
            return new Response(`Invalid request: ${e}`, {status: 400, headers: CORS_HEADERS});
        }
    }
}