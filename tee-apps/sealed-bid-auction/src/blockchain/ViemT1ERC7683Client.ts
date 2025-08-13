import {encodeAbiParameters, getContract} from "viem";

import t1Erc7683Artifact from "../../../../contracts/artifacts/src/T1ERC7683.sol/T1ERC7683.json";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import type {ViemBlockchainClient} from "./ViemBlockchainClient.ts";
import type {AuctionResult} from "../api/types.ts";
import type {OrderData} from "./types.ts";

export class ViemT1ERC7683Client {
    private logger: WinstonLogger;

    private readonly t1Erc7683Contract;

    constructor(t1Erc7683ContractAddress: `0x${string}`, private readonly client: ViemBlockchainClient) {
        this.t1Erc7683Contract = getContract({
            address: t1Erc7683ContractAddress,
            abi: t1Erc7683Artifact.abi,
            client: {
                public: client.publicClient, wallet: client.walletClient
            }
        });

        this.logger = new WinstonLogger(`${ViemT1ERC7683Client.name}[${client.publicClient.chain.name}]`);
    }

    public async commitWinnerBid(result: AuctionResult): Promise<`0x${string}`> {
        try {
            return await this.t1Erc7683Contract.write.commitWinnerBid!([
                result.orderId,
                {
                    settlementReceiver: result.settlementReceiverAddress,
                    amountOut: result.amountOut
                }
            ]);
        } catch (error) {
            this.logger.error(`Failed to commit winner bid for orderId=${result.orderId}`, error);
            throw error;
        }
    }

    public async fill(result: AuctionResult): Promise<`0x${string}`> {
        try {
            const fillerData = encodeAbiParameters(
                [
                    { type: 'uint256', name: 'amountOut' },
                    { type: 'address', name: 'settlementReceiver' },
                ],
                [result.amountOut, result.settlementReceiverAddress as `0x${string}`]
            )

            return await this.t1Erc7683Contract.write.fill!(
                [result.orderId, this.encodeOrderData(result.orderData), fillerData],
                {
                    account: this.client.walletClient.account, // ensure it's set
                    // maxFeePerGas: BigInt(20_000_000_000), // 20 gwei
                    // maxPriorityFeePerGas: BigInt(2_000_000_000), // 2 gwei
                }
            );
        } catch (error) {
            this.logger.error(`Failed to fillIntent orderId=${result.orderId}`, error);
        }
    }

    private encodeOrderData(orderData: OrderData): `0x${string}` {
        return encodeAbiParameters(
            [
                { type: "address" },
                { type: "address" },
                { type: "address" },
                { type: "address" },
                { type: "uint256" },
                { type: "uint256" },
                { type: "uint256" },
                { type: "uint32" },
                { type: "uint32" },
                { type: "address" },
                { type: "uint256" },
                { type: "bool" },
                { type: "bytes" },
            ],
            [
                orderData.sender,
                orderData.recipient,
                orderData.inputToken,
                orderData.outputToken,
                BigInt(orderData.amountIn),
                BigInt(orderData.minAmountOut),
                BigInt(orderData.senderNonce),
                orderData.originDomain,
                orderData.destinationDomain,
                orderData.destinationSettler,
                BigInt(orderData.fillDeadline),
                orderData.closedAuction,
                orderData.data,
            ]
        );
    }
}