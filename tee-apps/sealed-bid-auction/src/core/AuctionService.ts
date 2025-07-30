import Immutable from "immutable";

import type {AuctionQuote, AuctionRequest} from "../api/types.ts";
import type {SolverPriceBook} from "./SolverPriceBook.ts";
import type {Interval, PriceListItem} from "./types.ts";

export type Price = {
    price: bigint;
    solverAddress: string;
}

export class AuctionService {
    constructor(private readonly solverPricebook: SolverPriceBook) {}

    public preauction(request: AuctionRequest): AuctionQuote | null {
        const bestPrice = this.auction(request.srcTokenAddress, request.dstTokenAddress, request.amountIn);

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

    public auction(srcTokenAddress: string, dstTokenAddress: string, amountIn: bigint) {
        const pricesForAskedTokens = this.findPricesForAskedTokens(srcTokenAddress, dstTokenAddress, amountIn);

        return this.chooseBestPrice(pricesForAskedTokens);
    }

    private getCorrectInterval(priceListItem: PriceListItem, amount: bigint): Interval | undefined {
        return priceListItem.intervals.find(interval => interval.range.min <= amount && interval.range.max >= amount);
    }

    private chooseBestPrice(pricesForAskedTokens: Immutable.List<Price>): Price | null {
        let bestPrice = null;

        if (!pricesForAskedTokens.isEmpty()) {
            let bestPrice = {
                price: -1n,
                solverAddress: "0xdeadbeef"
            };

            pricesForAskedTokens.forEach(price => {
                if (price.price > bestPrice.price) bestPrice = price;
            });
        }

        return bestPrice;
    }

    private findPricesForAskedTokens(srcTokenAddress: string, dstTokenAddress: string, amountIn: bigint) {
        return this.solverPricebook.getCurrentPrices().flatMap(
            priceItems => priceItems.filter(
                priceItem =>
                    priceItem.srcTokenAddresses.includes(srcTokenAddress) &&
                    priceItem.dstTokenAddress.includes(dstTokenAddress) &&
                    this.getCorrectInterval(priceItem, amountIn) !== undefined
            ).map(priceItem => {
                return {
                    price: this.getCorrectInterval(priceItem, amountIn)!.price,
                    solverAddress: priceItem.solverAddress
                };
            })
        )
    }
}