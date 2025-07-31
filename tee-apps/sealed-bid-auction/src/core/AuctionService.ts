import Immutable from "immutable";

import type {AuctionQuote, AuctionRequest} from "../api/types.ts";
import type {SolverPriceBook} from "./SolverPriceBook.ts";
import type {PriceListItem} from "./types.ts";

type Price = {
    amountOut: bigint;
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
                amountOut: bestPrice.amountOut,
                solverAddress: bestPrice.solverAddress,
                timestamp: Date.now()
            };
        }
    }

    private getFinalIntervalIndex(priceListItem: PriceListItem, amount: bigint): number | undefined {
        return priceListItem.intervals.findIndex(interval => interval.range.min <= amount && interval.range.max >= amount);
    }

    private chooseBestPrice(pricesForAskedTokens: Immutable.List<Price>): Price | null {
        let bestPrice = null;

        if (!pricesForAskedTokens.isEmpty()) {
            let bestPrice: Price = {
                amountOut: -1n,
                solverAddress: "0xdeadbeef"
            };

            pricesForAskedTokens.forEach(price => {
                if (price.amountOut > bestPrice.amountOut) bestPrice = price;
            });
        }

        return bestPrice;
    }

    private findPricesForAskedTokens(request: AuctionRequest): Immutable.List<Price> {
        return this.solverPricebook.getCurrentPrices().flatMap(
            priceItems => priceItems.filter(
                priceItem =>
                    priceItem.srcTokenAddresses.includes(request.srcTokenAddress) &&
                    priceItem.dstTokenAddress.includes(request.dstTokenAddress) &&
                    this.getFinalIntervalIndex(priceItem, request.amountIn) !== undefined
            ).map(priceItem => {
                return {
                    amountOut: this.calculateAmountOut(priceItem, request.amountIn),
                    solverAddress: priceItem.solverAddress
                };
            })
        )
    }

    private calculateAmountOut(priceItem: PriceListItem, amountIn: bigint): bigint {
        let currentInterval = 0;
        let amountOut = 0n;
        const finalIndex = this.getFinalIntervalIndex(priceItem, amountIn)!;

        do {
            const curr = priceItem.intervals[currentInterval]!;
            const final = priceItem.intervals[finalIndex]!;
            if (curr !== final) {
                amountOut += curr.price * (curr.range.max - curr.range.min);
            } else {
                amountOut += curr.price * (amountIn - curr.range.min - (finalIndex === 0 ? 0n : 1n));
            }
        } while (priceItem.intervals[currentInterval++] !== priceItem.intervals[finalIndex]);

        return amountOut;
    }
}