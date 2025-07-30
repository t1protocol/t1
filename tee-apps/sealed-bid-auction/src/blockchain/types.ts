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
    data: string;
}
