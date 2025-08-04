export type OrderData = {
    sender: string;
    recipient: string;
    inputToken: string;
    outputToken: string;
    amountIn: bigint;
    minAmountOut: bigint;
    senderNonce: bigint;
    originDomain: bigint;
    destinationDomain: bigint;
    destinationSettler: string;
    fillDeadline: bigint;
    closedAuction: boolean;
    data: string;
}

export const convertSolidityOrderDataToTypescriptOrderData = (
    parsedAbi: readonly [`0x${string}`, `0x${string}`, `0x${string}`, `0x${string}`,
        bigint, bigint, bigint, bigint, bigint, `0x${string}`, bigint, boolean, `0x${string}`]): OrderData => {
    return {
        sender: parsedAbi[0],
        recipient: parsedAbi[1],
        inputToken: parsedAbi[2],
        outputToken: parsedAbi[3],
        amountIn: parsedAbi[4],
        minAmountOut: parsedAbi[5],
        senderNonce: parsedAbi[6],
        originDomain: parsedAbi[7],
        destinationDomain: parsedAbi[8],
        destinationSettler: parsedAbi[9],
        fillDeadline: parsedAbi[10],
        closedAuction: parsedAbi[11],
        data: parsedAbi[12]
    };
};

export const OPEN_INTENT_EVENT_SIGNATURE = 'event Open(bytes32 indexed orderId, bytes32 resolvedOrder)';

export const RESOLVER_ORDER_ABI_PARAMETERS = 'string user, uint originChainId, uint openDeadline, ' +
 'uint fillDeadline, bytes orderId, bytes maxSpent, bytes minReceived, bytes fillInstructions';

export const FILL_INSTRUCTION_ABI_PARAMETERS = '[uint destinationChainId, bytes destinationSettler, bytes originData]';

export const ORDER_DATA_ABI_PARAMETERS = 'bytes sender, bytes recipient, bytes inputToken, bytes outputToken, uint amountIn, uint minAmountOut, uint senderNonce, uint originDomain, uint destinationDomain, bytes destinationSettler, uint fillDeadline, bool closedAuction, bytes data';