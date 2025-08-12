import {encodeAbiParameters, getContract} from "viem";

import t1Erc7683Artifact from "../../../../contracts/artifacts/src/T1ERC7683.sol/T1ERC7683.json";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import type {ViemBlockchainClient} from "./ViemBlockchainClient.ts";
import type {AuctionResult} from "../api/types.ts";

export class ViemT1ERC7683Client {
    private logger: WinstonLogger;

    private readonly t1Erc7683Contract;

    constructor(t1Erc7683ContractAddress: `0x${string}`, client: ViemBlockchainClient) {
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

            return await this.t1Erc7683Contract.write.fill!([result.orderId, result.orderData, fillerData]);
        } catch (error) {
            this.logger.error(`Failed to fillIntent orderId=${result.orderId}`, error);
            throw error;
        }
    }
}