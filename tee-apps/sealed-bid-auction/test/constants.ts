export const USERNAME = "Bob";
export const PRIVATE_KEY = "0x59c6995e998f97a5a0044972fae75ce4e226e1b648b7387c86b3cf41c163a5fc";
export const SOLVER_ADDRESS = "0x293803aCe64D9B3f3DE141855d3D5810df478fcd";

export const PRICE_LIST_WITH_TWO_ITEMS = [{
            "direction": "Base_USDC->Arbitrum_USDC",
            "intervals": [
                {
                    "range": {
                        "min": "0",
                        "max": "99"
                    },
                    "rangeUnit": 0,
                    "price": "970000",
                    "priceUnit": 2
                },
                {
                    "range": {
                        "min": "100",
                        "max": "1000"
                    },
                    "rangeUnit": 0,
                    "price": "980000",
                    "priceUnit": 2
                }
            ],
            "srcTokenAddresses": ["0xf3C3351D6Bd0098EEb33ca8f830FAf2a141Ea2E1"],
            "destTokenAddresses": ["0x036CbD53842c5426634e7929541eC2318f3dCF7e"],
            "settlementReceiverAddress": SOLVER_ADDRESS
        },
        {
            "direction": "Arbitrum_WETH",
            "intervals": [
                {
                    "range": {
                        "min": "0",
                        "max": "3"
                    },
                    "rangeUnit": 3,
                    "price": "3500000000",
                    "priceUnit": 0
                },
                {
                    "range": {
                        "min": "4",
                        "max": "18"
                    },
                    "rangeUnit": 3,
                    "price": "3480000000",
                    "priceUnit": 0
                }
            ],
            "srcTokenAddresses": ["0x036CbD53842c5426634e7929541eC2318f3dCF7e"],
            "destTokenAddresses": ["0xf3C3351D6Bd0098EEb33ca8f830FAf2a141Ea2E1"],
            "settlementReceiverAddress": SOLVER_ADDRESS
        }];

export const PRICE_LIST_WITH_GAP_IN_RANGES = [{
    "direction": "Base_USDC->Arbitrum_USDC",
    "intervals": [
        {
            "range": {
                "min": "0",
                "max": "99"
            },
            "rangeUnit": 0,
            "price": "970000",
            "priceUnit": 2
        },
        {
            "range": {
                "min": "101",
                "max": "1000"
            },
            "rangeUnit": 0,
            "price": "980000",
            "priceUnit": 2
        }
    ],
    "srcTokenAddresses": ["0xf3C3351D6Bd0098EEb33ca8f830FAf2a141Ea2E1"],
    "destTokenAddresses": ["0x036CbD53842c5426634e7929541eC2318f3dCF7e"],
    "settlementReceiverAddress": SOLVER_ADDRESS
},
    {
        "direction": "Arbitrum_WETH",
        "intervals": [
            {
                "range": {
                    "min": "0",
                    "max": "3"
                },
                "rangeUnit": 3,
                "price": "3500000000",
                "priceUnit": 0
            },
            {
                "range": {
                    "min": "4",
                    "max": "18"
                },
                "rangeUnit": 3,
                "price": "3480000000",
                "priceUnit": 0
            }
        ],
        "srcTokenAddresses": ["0x036CbD53842c5426634e7929541eC2318f3dCF7e"],
        "destTokenAddresses": ["0xf3C3351D6Bd0098EEb33ca8f830FAf2a141Ea2E1"],
        "settlementReceiverAddress": SOLVER_ADDRESS
    }];