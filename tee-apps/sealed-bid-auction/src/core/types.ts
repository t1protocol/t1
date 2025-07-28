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
        min: number; // must be an integer representing full tokens
        max: number; // must be an integer representing full tokens
    };
    rangeUnit: Token;
    price: number; // must be an integer representing the smallest denomination of the token
    priceUnit: Token;
};
