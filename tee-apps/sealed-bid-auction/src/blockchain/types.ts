export type OrderData = {
    sender: string;
    recipient: string;
    inputToken: string;
    outputToken: string;
    amountIn: bigint;
    minAmountOut: bigint;
    senderNonce: number;
    originDomain: number;
    destinationDomain: number;
    destinationSettler: string;
    fillDeadline: number;
    closedAuction: boolean;
    data: string;
};

export const OPEN_INTENT_ABI_EVENT = {"name":"Open","type":"event","inputs":[{"name":"orderId","type":"bytes32","indexed":true},{"name":"resolvedOrder","type":"tuple","indexed":false,"components":[{"name":"user","type":"address"},{"name":"originChainId","type":"uint256"},{"name":"openDeadline","type":"uint32"},{"name":"fillDeadline","type":"uint32"},{"name":"orderId","type":"bytes32"},{"name":"maxSpent","type":"tuple[]","components":[{"name":"token","type":"bytes32"},{"name":"amount","type":"uint256"},{"name":"recipient","type":"bytes32"},{"name":"chainId","type":"uint256"}]},{"name":"minReceived","type":"tuple[]","components":[{"name":"token","type":"bytes32"},{"name":"amount","type":"uint256"},{"name":"recipient","type":"bytes32"},{"name":"chainId","type":"uint256"}]},{"name":"fillInstructions","type":"tuple[]","components":[{"name":"destinationChainId","type":"uint256"},{"name":"destinationSettler","type":"bytes32"},{"name":"originData","type":"bytes"}]}]}]}

export const ORDER_DATA_ABI_PARAMETERS_WRAPPED_IN_TUPLE = [
    {
        type: 'tuple',
        name: 'order',
        components: [
            { name: 'sender', type: 'bytes32' },
            { name: 'recipient', type: 'bytes32' },
            { name: 'inputToken', type: 'bytes32' },
            { name: 'outputToken', type: 'bytes32' },
            { name: 'amountIn', type: 'uint256' },
            { name: 'minAmountOut', type: 'uint256' },
            { name: 'senderNonce', type: 'uint256' },
            { name: 'originDomain', type: 'uint32' },
            { name: 'destinationDomain', type: 'uint32' },
            { name: 'destinationSettler', type: 'bytes32' },
            { name: 'fillDeadline', type: 'uint32' },
            { name: 'closedAuction', type: 'bool' },
            { name: 'data', type: 'bytes' },
        ],
    },
];