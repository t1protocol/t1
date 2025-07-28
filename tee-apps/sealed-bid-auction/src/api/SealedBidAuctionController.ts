import type {BunRequest} from "bun";
import {AuctionService} from "../core/AuctionService.ts";
import type {PreauctionRequest} from "./types.ts";
import type {SolverPriceBook} from "../core/SolverPriceBook.ts";

export class SealedBidAuctionController {

    private readonly auctionService;

    constructor(private readonly solverPricebook: SolverPriceBook) {
        this.auctionService = new AuctionService(this.solverPricebook);
    }

    public async preauction(req: BunRequest): Promise<Response> {
        try {
            const preauctionRequest: PreauctionRequest = JSON.parse(await req.text());

            return new Response("", {status: 200})
        } catch (e: any) {
            return new Response(`Invalid request: ${e}`, {status: 400})
        }
    }
}