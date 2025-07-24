import {ALL_DIRECTIONS, type Interval, type PriceList} from "./types.ts";

export class SolverPriceBook {
    private prices: Map<string, PriceList> = new Map<string, PriceList>();

    updatePrice(username: string, priceBlob: string): number {
        const priceList = this.validatePriceList(priceBlob);

        this.prices.set(username, priceList);

        return Object.keys(priceList).length;
    }

    private validatePriceList(priceBlob: string): PriceList {
        const priceList: PriceList = JSON.parse(priceBlob);

        ALL_DIRECTIONS.forEach((direction) => {
            const intervals: Interval[] | undefined = priceList[direction];
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