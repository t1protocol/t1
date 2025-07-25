import type {BunRequest} from "bun";

export class SealedBidAuctionController {
    async auction(req: BunRequest): Promise<Response> {
        return new Response("Not Implemented", {status: 501});
    }
}