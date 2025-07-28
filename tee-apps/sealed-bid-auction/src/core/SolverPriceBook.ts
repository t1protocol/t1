import {ALL_DIRECTIONS, type Interval, type PriceList} from "./types.ts";

type PriceBookEntry = {
    timestamp: number;
    priceList: PriceList;
}

export class SolverPriceBook {
    private prices: Map<string, PriceBookEntry> = new Map<string, PriceBookEntry>();

    updatePrice(username: string, priceBlob: string): number {
        const priceList = this.validatePriceList(priceBlob);

        this.prices.set(username, { priceList, timestamp: Date.now() });

        return Object.keys(priceList).length;
    }

    private validatePriceList(priceBlob: string): PriceList {
        const priceList: PriceList = JSON.parse(priceBlob);

        ALL_DIRECTIONS.forEach((direction) => {
            const intervals: Interval[] | undefined = priceList[direction].intervals;
            if (intervals) {
                for (let i = 1; i < intervals.length; i++) {
                    if (BigInt(intervals[i - 1]!.range.max) + 1n !== BigInt(intervals[i]!.range.min)) {
                        throw new Error(`There is a gap between max of range [${i - 1}] and min of range [${i}]`);
                    }
                }
            }
        });

        return priceList;
    }
}