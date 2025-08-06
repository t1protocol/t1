import Immutable from "immutable";

import type {AuctionQuote, AuctionRequest} from "../api/types.ts";
import type {SolverPriceBook} from "./SolverPriceBook.ts";
import type {PriceListItem} from "./types.ts";
import {serialize, WinstonLogger} from "../utils/WinstonLogger.ts";

export type Price = {
    amountOut: bigint;
    settlementReceiverAddress: string;
}

export class AuctionService {
    private logger = new WinstonLogger(AuctionService.name);

    constructor(private readonly solverPricebook: SolverPriceBook) {}

    public preauction(request: AuctionRequest): AuctionQuote | null {
        const bestPrice = this.auction(request.srcTokenAddress, request.dstTokenAddress, request.amountIn);

        if (!bestPrice) {
            return null;
        } else {
            return {
                id: request.id,
                request: request as Omit<AuctionRequest, "id">,
                amountOut: bestPrice.amountOut,
                settlementReceiverAddress: bestPrice.settlementReceiverAddress,
                timestamp: Date.now()
            };
        }
    }

    public auction(srcTokenAddress: string, dstTokenAddress: string, amountIn: bigint): Price | null {
        const pricesForAskedTokens = this.findPricesForAskedTokens(srcTokenAddress, dstTokenAddress, amountIn);

        this.logger.debug(`Found these prices for asked tokens: ${serialize(pricesForAskedTokens)}`);

        return this.chooseBestPrice(pricesForAskedTokens);
    }

    private getFinalIntervalIndex(priceListItem: PriceListItem, amount: bigint): number | undefined {
        return priceListItem.intervals.findIndex(interval => interval.range.min <= amount && interval.range.max >= amount);
    }

    private chooseBestPrice(pricesForAskedTokens: Immutable.List<Price>): Price | null {
        let bestPrice: Price | null = null;

        if (!pricesForAskedTokens.isEmpty()) {
            bestPrice = {
                amountOut: -1n,
                settlementReceiverAddress: "0xdeadbeef"
            };

            pricesForAskedTokens.forEach(price => {
                if (price.amountOut > bestPrice!.amountOut) bestPrice = price;
            });
        }

        return bestPrice;
    }

    private findPricesForAskedTokens(srcTokenAddress: string, dstTokenAddress: string, amountIn: bigint): Immutable.List<Price> {
        return this.solverPricebook.getCurrentPrices().flatMap(
            priceItems => priceItems.filter(
                priceItem =>
                    priceItem.srcTokenAddresses.includes(srcTokenAddress) &&
                    priceItem.dstTokenAddresses.includes(dstTokenAddress) &&
                    this.getFinalIntervalIndex(priceItem, amountIn) !== undefined
            ).map(priceItem => {
                return {
                    amountOut: this.calculateAmountOut(priceItem, amountIn),
                    settlementReceiverAddress: priceItem.settlementReceiverAddress
                };
            })
        )
    }

    private calculateAmountOut(priceItem: PriceListItem, amountIn: bigint): bigint {
        let currentIntervalIndex = 0;
        let amountOut = 0n;
        const finalIndex = this.getFinalIntervalIndex(priceItem, amountIn)!;

        do {
            const currInterval = priceItem.intervals[currentIntervalIndex]!;
            if (currInterval !== priceItem.intervals[finalIndex]!) {
                amountOut += currInterval.price * (currInterval.range.max - (currentIntervalIndex === 0 ? 0n : currInterval.range.min));
            } else {
                amountOut += currInterval.price * (amountIn - (currentIntervalIndex === 0 ? 0n : currInterval.range.min) + (finalIndex === 0 ? 0n : 1n));
            }
        } while (priceItem.intervals[currentIntervalIndex++] !== priceItem.intervals[finalIndex]);

        return amountOut;
    }
}