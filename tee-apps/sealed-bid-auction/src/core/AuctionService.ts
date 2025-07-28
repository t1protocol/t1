import Immutable from "immutable";

import type {AuctionQuote, AuctionRequest} from "../api/types.ts";
import type {SolverPriceBook} from "./SolverPriceBook.ts";
import type {Interval, PriceListItem} from "./types.ts";

type Price = {
    price: number;
    solverAddress: string;
}

export class AuctionService {
    constructor(private readonly solverPricebook: SolverPriceBook) {}

    public auction(request: AuctionRequest): AuctionQuote | null {
        const pricesForAskedTokens = this.findPricesForAskedTokens(request);

        const bestPrice = this.chooseBestPrice(pricesForAskedTokens);

        if (!bestPrice) {
            throw new Error("No quote found for this pair");
        } else {
            return {
                id: request.id,
                request: request as Omit<AuctionRequest, "id">,
                amountOut: bestPrice.price,
                solverAddress: bestPrice.solverAddress,
                timestamp: Date.now()
            };
        }
    }

    private getCorrectInterval(priceListItem: PriceListItem, amount: number): Interval | undefined {
        return priceListItem.intervals.find(interval => interval.range.min <= amount && interval.range.max >= amount);
    }

    private chooseBestPrice(pricesForAskedTokens: Immutable.List<Price>): Price | null {
        let bestPrice = null;

        if (!pricesForAskedTokens.isEmpty()) {
            let bestPrice = {
                price: -1,
                solverAddress: "0xdeadbeef"
            };

            pricesForAskedTokens.forEach(price => {
                if (price.price > bestPrice.price) bestPrice = price;
            });
        }

        return bestPrice;
    }

    private findPricesForAskedTokens(request: AuctionRequest) {
        return this.solverPricebook.getCurrentPrices().flatMap(
            priceItems => priceItems.filter(
                priceItem =>
                    priceItem.srcTokenAddresses.includes(request.srcTokenAddress) &&
                    priceItem.dstTokenAddress.includes(request.dstTokenAddress) &&
                    this.getCorrectInterval(priceItem, request.amountIn) !== undefined
            ).map(priceItem => {
                return {
                    price: this.getCorrectInterval(priceItem, request.amountIn)!.price,
                    solverAddress: priceItem.solverAddress
                };
            })
        )
    }
}