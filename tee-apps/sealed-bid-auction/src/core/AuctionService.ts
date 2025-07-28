import type {PreauctionQuote, PreauctionRequest} from "../api/types.ts";
import type {SolverPriceBook} from "./SolverPriceBook.ts";

export class AuctionService {
    constructor(private readonly solverPricebook: SolverPriceBook) {}

    // public preauction(request: PreauctionRequest): PreauctionQuote {
    //     let prices = this.solverPricebook.getCurrentPrices().filter(
    //         price => price.
    //     );
    //
    // }
}