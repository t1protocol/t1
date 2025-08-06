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

export const convertSolidityOrderDataToTypescriptOrderData = (
    decoded: readonly [`0x${string}`, `0x${string}`, `0x${string}`, `0x${string}`,
        bigint, bigint, number, number, number, `0x${string}`, number, boolean, `0x${string}`]): OrderData => {
    return {
        sender: decoded[0],
        recipient: decoded[1],
        inputToken: decoded[2],
        outputToken: decoded[3],
        amountIn: BigInt(decoded[4]),
        minAmountOut: BigInt(decoded[5]),
        senderNonce: decoded[6],
        originDomain: decoded[7],
        destinationDomain: decoded[8],
        destinationSettler: decoded[9],
        fillDeadline: decoded[10],
        closedAuction: decoded[11],
        data: decoded[12],
    };
};

export const OPEN_INTENT_ABI_EVENT = {"name":"Open","type":"event","inputs":[{"name":"orderId","type":"bytes32","indexed":true},{"name":"resolvedOrder","type":"tuple","indexed":false,"components":[{"name":"user","type":"address"},{"name":"originChainId","type":"uint256"},{"name":"openDeadline","type":"uint32"},{"name":"fillDeadline","type":"uint32"},{"name":"orderId","type":"bytes32"},{"name":"maxSpent","type":"tuple[]","components":[{"name":"token","type":"bytes32"},{"name":"amount","type":"uint256"},{"name":"recipient","type":"bytes32"},{"name":"chainId","type":"uint256"}]},{"name":"minReceived","type":"tuple[]","components":[{"name":"token","type":"bytes32"},{"name":"amount","type":"uint256"},{"name":"recipient","type":"bytes32"},{"name":"chainId","type":"uint256"}]},{"name":"fillInstructions","type":"tuple[]","components":[{"name":"destinationChainId","type":"uint256"},{"name":"destinationSettler","type":"bytes32"},{"name":"originData","type":"bytes"}]}]}]}

export const ORDER_DATA_ABI_PARAMETERS = 'bytes32 sender,bytes32 recipient,bytes32 inputToken,bytes32 outputToken,uint256 amountIn,uint256 minAmountOut,uint256 senderNonce,uint32 originDomain,uint32 destinationDomain,bytes32 destinationSettler,uint32 fillDeadline,bool closedAuction,bytes data';
