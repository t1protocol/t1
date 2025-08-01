import { List as ImmutableList } from 'immutable';

import {type PriceListItem} from "./types.ts";

type PriceBookEntry = {
    timestamp: number;
    priceList: PriceListItem[];
}

export class SolverPriceBook {
    private prices: Map<string, PriceBookEntry> = new Map<string, PriceBookEntry>();
    private authenticatedAddresses: Set<string> = new Set();

    constructor(private readonly priceListTTL: number = 600) {}

    public getCurrentPrices(): ImmutableList<PriceListItem[]> {
        return ImmutableList(
            this.prices.entries()
                .filter(([_key, value]) => value.timestamp > Date.now() + this.priceListTTL)
                .map(([_key, value]) => value.priceList)
        );
    }

    public authenticateSolver(address: string): void {
        this.authenticatedAddresses.add(address.toLowerCase());
    }

    public logoutSolver(address: string): void {
        this.authenticatedAddresses.delete(address.toLowerCase());
    }

    public isAuthenticated(address: string): boolean {
        return this.authenticatedAddresses.has(address.toLowerCase());
    }

    public updatePrice(username: string, priceBlob: string): number {
        const priceList = this.validatePriceList(priceBlob);

        this.prices.set(username, { priceList, timestamp: Date.now() });

        return Object.keys(priceList).length;
    }

    private validatePriceList(priceBlob: string): PriceListItem[] {
        const priceList: PriceListItem[] = JSON.parse(priceBlob);

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
}