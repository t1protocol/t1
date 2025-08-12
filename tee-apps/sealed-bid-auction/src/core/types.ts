export type PriceListItem = {
    direction: Direction;
    intervals: Interval[];
    srcTokenAddresses: `0x${string}`[];
    dstTokenAddresses: `0x${string}`[];
    settlementReceiverAddress: `0x${string}`;
    srcChainId: number;
    dstChainId: number;
}

export enum Direction {
    "Base_USDC->Arbitrum_USDC",
    "Base_USDC->Arbitrum_WETH",
    "Arbitrum_USDC->Base_USDC",
    "Arbitrum_WETH->Base_USDC",
}

export enum Token {
    Base_USDC = "Base_USDC",
    Base_WETH = "Base_WETH",
    Arbitrum_USDC = "Arbitrum_USDC",
    Arbitrum_WETH = "Arbitrum_WETH",
}

export interface TokenWithDecimal {
    token: Token,
    decimal: bigint
}

export type Interval = {
    range: {
        min: bigint; // must be an integer representing full tokens
        max: bigint; // must be an integer representing full tokens
    };
    rangeUnit: TokenWithDecimal;
    price: bigint; // must be an integer representing the smallest denomination of the token
    priceUnit: TokenWithDecimal;
};
