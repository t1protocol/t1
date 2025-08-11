import {getContract} from "viem";

import t1Erc7683Artifact from "../../../../contracts/artifacts/src/T1ERC7683.sol/T1ERC7683.json";
import {WinstonLogger} from "../utils/WinstonLogger.ts";
import type {BlockchainClient} from "./BlockchainClient.ts";
import type {AuctionResult} from "../api/types.ts";

export class ViemAuctionCommiter {
    private logger: WinstonLogger;

    private readonly t1Erc7683Contract;

    constructor(t1Erc7683ContractAddress: `0x${string}`, client: BlockchainClient) {
        this.t1Erc7683Contract = getContract({
            address: t1Erc7683ContractAddress,
            abi: t1Erc7683Artifact.abi,
            client: {
                public: client.publicClient, wallet: client.walletClient
            }
        });

        this.logger = new WinstonLogger(`${ViemAuctionCommiter.name}[${client.publicClient.chain.name}]`);
    }

    public async test() {
        const localDomain = await this.t1Erc7683Contract.read.owner!();

        this.logger.info(`I connected to t1erc7683 at address=[${this.t1Erc7683Contract.address}] . I read owner=[${localDomain}] from it.`);
    }

    public async commitWinnerBid(result: AuctionResult): Promise<`0x${string}`> {
        return await this.t1Erc7683Contract.write.commitWinnerBid!([
            result.orderId, {
                settlementReceiver: result.settlementReceiverAddress,
                amountOut: result.amountOut
            }
        ]);
    }
}