import {Direction, type PriceListItem, Token} from "../core/types.ts";
import {arbitrumSepolia, baseSepolia} from "viem/chains";

export const ATTRACTIVE_ARBITRUM_PRICE: PriceListItem[] = [{
    direction: Direction["Base_USDC->Arbitrum_USDC"],
    intervals: [
        {
            "range": {
                "min": 0n,
                "max": 99n
            },
            "rangeUnit": {
                token: Token["Base_USDC"],
                decimal: 6n
            },
            "price": 970_000n,
            "priceUnit": {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            }
        },
        {
            "range": {
                "min": 100n,
                "max": 1000n
            },
            "rangeUnit": {
                token: Token["Base_USDC"],
                decimal: 6n
            },
            "price": 980_000n,
            "priceUnit": {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            }
        }
    ],
    srcTokenAddresses: ["0x228eE6c1C297E2Eba0e95A71684B26f89385b4eC"],
    dstTokenAddresses: ["0xF6232a871BF3B33F5bc181f55d770F9FB062A457"],
    settlementReceiverAddress: "0xa3e5e908868E2D881E70c304C18636A2f43E933f",
    srcChainId: baseSepolia.id,
    dstChainId: arbitrumSepolia.id
},
    {
        direction: Direction["Arbitrum_USDC->Base_USDC"],
        intervals: [
            {
                "range": {
                    min: 0n,
                    max: 99n
                },
                rangeUnit: {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            },
                price: 950_000n,
                priceUnit: {
                token: Token["Base_USDC"],
                decimal: 6n
            }
            },
            {
                "range": {
                    min: 100n,
                    max: 1000n
                },
                rangeUnit: {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            },
                price: 960_000n,
                priceUnit: {
                token: Token["Base_USDC"],
                decimal: 6n
            }
            }
        ],
        srcTokenAddresses: ["0xF6232a871BF3B33F5bc181f55d770F9FB062A457"],
        dstTokenAddresses: ["0x228eE6c1C297E2Eba0e95A71684B26f89385b4eC"],
        settlementReceiverAddress: "0xa3e5e908868E2D881E70c304C18636A2f43E933f",
        srcChainId: arbitrumSepolia.id,
        dstChainId: baseSepolia.id
    }];

export const ATTRACTIVE_BASE_PRICE: PriceListItem[] = [{
    direction: Direction["Base_USDC->Arbitrum_USDC"],
    intervals: [
        {
            "range": {
                min: 0n,
                max: 99n
            },
            rangeUnit: {
                token: Token["Base_USDC"],
                decimal: 6n
            },
            price: 950_000n,
            priceUnit: {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            }
        },
        {
            "range": {
                min: 100n,
                max: 1000n
            },
            rangeUnit: {
                token: Token["Base_USDC"],
                decimal: 6n
            },
            price: 960_000n,
            priceUnit: {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            }
        }
    ],
    srcTokenAddresses: ["0x228eE6c1C297E2Eba0e95A71684B26f89385b4eC"],
    dstTokenAddresses: ["0xF6232a871BF3B33F5bc181f55d770F9FB062A457"],
    settlementReceiverAddress: "0xD99c1b45708a4E94c6230f6A77BD7fa729f5398B",
    srcChainId: baseSepolia.id,
    dstChainId: arbitrumSepolia.id
},
    {
        direction: Direction["Arbitrum_USDC->Base_USDC"],
        intervals: [
            {
                "range": {
                    min: 0n,
                    max: 99n
                },
                rangeUnit: {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            },
                price: 970_000n,
                priceUnit: {
                token: Token["Base_USDC"],
                decimal: 6n
            }
            },
            {
                "range": {
                    min: 100n,
                    max: 1000n
                },
                rangeUnit: {
                token: Token["Arbitrum_USDC"],
                decimal: 6n
            },
                price: 980_000n,
                priceUnit: {
                token: Token["Base_USDC"],
                decimal: 6n
            }
            }
        ],
        srcTokenAddresses: ["0xF6232a871BF3B33F5bc181f55d770F9FB062A457"],
        dstTokenAddresses: ["0x228eE6c1C297E2Eba0e95A71684B26f89385b4eC"],
        settlementReceiverAddress: "0xD99c1b45708a4E94c6230f6A77BD7fa729f5398B",
        srcChainId: arbitrumSepolia.id,
        dstChainId: baseSepolia.id
    }];