export type PriceListItem = {
    direction: Direction;
    intervals: Interval[];
    srcTokenAddresses: string[];
    dstTokenAddress: string[];
    solverAddress: string;
}

export enum Direction {
    "Base_USDC->Arbitrum_USDC",
    "Base_USDC->Arbitrum_WETH",
    "Arbitrum_USDC->Base_USDC",
    "Arbitrum_WETH->Base_USDC",
}

enum Token {
    Base_USDC = "Base_USDC",
    Base_WETH = "Base_WETH",
    Arbitrum_USDC = "Arbitrum_USDC",
    Arbitrum_WETH = "Arbitrum_WETH",
}

export type Interval = {
    range: {
        min: bigint; // must be an integer representing full tokens
        max: bigint; // must be an integer representing full tokens
    };
    rangeUnit: Token;
    price: bigint; // must be an integer representing the smallest denomination of the token
    priceUnit: Token;
};
