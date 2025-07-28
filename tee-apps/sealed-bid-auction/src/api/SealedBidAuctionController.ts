import type {BunRequest} from "bun";

import {AuctionService} from "../core/AuctionService.ts";
import type {AuctionRequest} from "./types.ts";

export class SealedBidAuctionController {

    constructor(private readonly auctionService: AuctionService) {}

    public async preauction(req: BunRequest): Promise<Response> {
        try {
            const auctionRequest: AuctionRequest = JSON.parse(await req.text());
            const auctionQuote = this.auctionService.auction(auctionRequest);

            if (auctionQuote) {
                return new Response(JSON.stringify(auctionQuote), {status: 200});
            } else {
                return new Response("No quote found for this pair", {status: 204});
            }

        } catch (e: any) {
            return new Response(`Invalid request: ${e}`, {status: 400});
        }
    }
}