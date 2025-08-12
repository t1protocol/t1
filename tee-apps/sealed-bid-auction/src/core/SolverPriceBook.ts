import { List as ImmutableList } from 'immutable';

import {type Interval, type PriceListItem} from "./types.ts";

type PriceBookEntry = {
    timestamp: number;
    priceList: PriceListItem[];
}

const TEN_MINUTES_IN_MS = 600_000;

export class SolverPriceBook {
    private prices: Map<string, PriceBookEntry> = new Map<string, PriceBookEntry>();

    constructor(private readonly priceListTTLseconds: number) {}

    public getCurrentPrices(): ImmutableList<PriceListItem[]> {
        return ImmutableList(
            this.prices.entries().toArray()
                .filter(([_key, value]) => value.timestamp + (this.priceListTTLseconds * 1000) > Date.now())
                .map(([_key, value]) => value.priceList)
        );
    }

    public updatePrice(username: string, priceBlob: string): number {
        const priceList = this.validatePriceList(priceBlob);

        this.prices.set(username, { priceList, timestamp: Date.now() });

        return Object.keys(priceList).length;
    }

    private validatePriceList(priceBlob: string): PriceListItem[] {
        let priceList: PriceListItem[] = JSON.parse(priceBlob);
        priceList = priceList.map(item => {
            return {
                direction: item.direction,
                intervals: item.intervals.map(interval => this.parseInterval(interval)),
                srcTokenAddresses: item.srcTokenAddresses,
                dstTokenAddresses: item.dstTokenAddresses,
                settlementReceiverAddress: item.settlementReceiverAddress,
            };
        });

        priceList.forEach((priceListItem) => {
            const intervals = priceListItem.intervals;
            for (let i = 1; i < intervals.length; i++) {
                if (BigInt(intervals[i - 1]!.range.max) + 1n !== BigInt(intervals[i]!.range.min)) {
                    throw new Error(`There is a gap between max of range [${i - 1}] and min of range [${i}]`);
                }
            }
        });

        return priceList;
    }

    private parseInterval(interval: Interval): Interval {
        return {
            range: {
                min: BigInt(interval.range.min),
                max: BigInt(interval.range.max),
            },
            rangeUnit: {
                token: interval.rangeUnit.token,
                decimal: BigInt(interval.rangeUnit.decimal)
            },
            price: BigInt(interval.price),
            priceUnit: {
                token: interval.priceUnit.token,
                decimal: BigInt(interval.priceUnit.decimal)
            }
        };
    }
}