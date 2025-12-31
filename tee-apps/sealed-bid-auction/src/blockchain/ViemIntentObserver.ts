import {
  decodeAbiParameters,
  parseEventLogs,
  trim,
  type WatchEventOnLogsParameter,
} from "viem";

import type { AuctionService } from "../core/AuctionService.ts";
import {
  OPEN_INTENT_ABI_EVENT,
  ORDER_DATA_ABI_PARAMETERS_WRAPPED_IN_TUPLE,
  type OrderData,
} from "./types.ts";
import type { AuctionApiServer } from "../api/AuctionApiServer.ts";
import { serialize, WinstonLogger } from "../utils/WinstonLogger.ts";
import type { BlockchainClient } from "./BlockchainClient.ts";
import type { AuctionResult, OpenEventLog } from "../api/types.ts";

const HISTORICAL_BLOCK_CHUNK_SIZE = 100n;

export class ViemIntentObserver {
  private logger: WinstonLogger;

  private websocketError: boolean = false;
  private lastProcessedBlock: bigint | null = null;
  
  constructor(
    private readonly sourceChainClient: BlockchainClient,
    private readonly sourceChainT1Erc7683ContractAddress: `0x${string}`,
    private readonly auctionService: AuctionService,
    private readonly apiServer: AuctionApiServer,
    private readonly destinationChainId: number,
    private readonly destinationChainT1Erc7683ContractAddress: `0x${string}`,
    private readonly auctionPollingInterval: number = 500,
    private readonly initialFromBlock: bigint | null
  ) {
    this.logger = new WinstonLogger(
      `${ViemIntentObserver.name}[${this.sourceChainClient.publicClient.chain.name}]`
    );
  }

  public async start() {
    if (this.initialFromBlock !== null) {
      await this.fetchHistoricalLogs(this.initialFromBlock);
    }

    this.startWatching();
  }

  private startWatching() {
    this.sourceChainClient.publicClient.watchEvent({
      address: this.sourceChainT1Erc7683ContractAddress,
      event: OPEN_INTENT_ABI_EVENT,
      onLogs: async (logs) => {
        if (this.websocketError && this.lastProcessedBlock) {
          await this.fetchHistoricalLogs(this.lastProcessedBlock + 1);
          this.websocketError = false;
        }
        await this.processIntentLogs(logs);
      },
      onError: (error) => {
        this.websocketError = true;
        this.logger.error(`Error from publicClient.watchEvent: ${error}`);
      },
    });

    this.logger.info(
      `Watching for Open Intent events on chain [${this.sourceChainClient.publicClient.chain.name}] and contract [${this.sourceChainT1Erc7683ContractAddress}]`
    );
  }

  private async fetchHistoricalLogs(fromBlock: bigint) {
    const currentBlock = await this.sourceChainClient.publicClient.getBlockNumber();
    this.logger.info(
      `Fetching historical logs from block ${fromBlock} to ${currentBlock}`
    );

    while (fromBlock <= currentBlock) {
      const toBlock = fromBlock + HISTORICAL_BLOCK_CHUNK_SIZE - 1n > currentBlock
        ? currentBlock
        : fromBlock + HISTORICAL_BLOCK_CHUNK_SIZE - 1n;

      this.logger.info(`Fetching logs from block ${fromBlock} to ${toBlock}`);

      const logs = await this.sourceChainClient.publicClient.getLogs({
        address: this.sourceChainT1Erc7683ContractAddress,
        event: OPEN_INTENT_ABI_EVENT,
        fromBlock,
        toBlock,
      });

      if (logs.length > 0) {
        this.logger.info(`Found ${logs.length} historical logs in blocks ${fromBlock}-${toBlock}`);
        await this.processIntentLogs(logs as unknown as WatchEventOnLogsParameter);
      }

      fromBlock = toBlock + 1n;
    }

    this.logger.info(`Finished fetching historical logs, caught up to block ${currentBlock}`);
  }

  private async processIntentLogs(logs: WatchEventOnLogsParameter) {
    this.logger.info("Intent was Open-ed!");

    const parsedLogs = parseEventLogs({
      abi: [OPEN_INTENT_ABI_EVENT],
      logs,
    });

    for (let i = 0; i < parsedLogs.length; i++) {
      const order = parsedLogs[i];
      const rawLog = logs[i]!;

      // Convert raw log to eth_getLogs hex format for tokka-filler
      const openEvent: OpenEventLog = {
        address: rawLog.address,
        topics: rawLog.topics as string[],
        data: rawLog.data,
        blockNumber: `0x${rawLog.blockNumber.toString(16)}`,
        transactionHash: rawLog.transactionHash,
        transactionIndex: `0x${rawLog.transactionIndex.toString(16)}`,
        blockHash: rawLog.blockHash,
        logIndex: `0x${rawLog.logIndex.toString(16)}`,
        removed: rawLog.removed,
      };

      for (const fillInstruction of order.args.resolvedOrder.fillInstructions) {
        const [decodedOrder] = decodeAbiParameters(
          ORDER_DATA_ABI_PARAMETERS_WRAPPED_IN_TUPLE,
          fillInstruction.originData
        );

        const orderData = decodedOrder as OrderData;

        this.runAuctionAndNotifySolver(
          {
            sender: trim(orderData.sender),
            recipient: trim(orderData.recipient),
            inputToken: trim(orderData.inputToken),
            outputToken: trim(orderData.outputToken),
            amountIn: BigInt(orderData.amountIn),
            minAmountOut: BigInt(orderData.minAmountOut),
            senderNonce: Number(orderData.senderNonce),
            originDomain: orderData.originDomain,
            destinationDomain: orderData.destinationDomain,
            destinationSettler: trim(orderData.destinationSettler),
            fillDeadline: orderData.fillDeadline,
            closedAuction: orderData.closedAuction,
            data: orderData.data,
          },
          order.args.orderId,
          openEvent
        ).then(() => this.lastProcessedBlock = BigInt(rawLog.blockNumber));
      }
    }
  }

  private async runAuctionAndNotifySolver(
    orderData: OrderData,
    orderId: `0x${string}`,
    openEvent: OpenEventLog
  ) {
    this.logger.info(`Running auction for order ${orderId}`);

    this.logger.debug(`Running auction for orderData ${serialize(orderData)}`);

    while (Date.now() / 1000 < orderData.fillDeadline) {
      let winningPrice;
      try {
        winningPrice = this.auctionService.auction(
          orderData.inputToken,
          orderData.outputToken,
          orderData.amountIn
        );
      } catch (e) {
        this.logger.error(`Auction error: ${e}`);
        break;
      }

      this.logger.debug(`Auction winner: ${serialize(winningPrice)}`);

      if (
        winningPrice !== null &&
        winningPrice.amountOut >= orderData.minAmountOut
      ) {
        const result: AuctionResult = {
          type: "winning-bid",
          settlementReceiverAddress: winningPrice.settlementReceiverAddress,
          amountOut: winningPrice.amountOut,
          orderId,
          signature: await this.signAuctionResult(
            orderId,
            winningPrice.settlementReceiverAddress as `0x${string}`,
            winningPrice.amountOut
          ),
          openEvent,
        };

        await this.apiServer.notifySolvers(
          result,
          this.sourceChainClient.publicClient.chain.id
        );

        this.logger.info(
          `I finished auction for orderId=[${orderId}] and notified solvers`
        );
        break;
      }

      await new Promise((resolve) =>
        setTimeout(resolve, this.auctionPollingInterval)
      );
    }
  }

  private async signAuctionResult(
      orderId: `0x${string}`,
      winningSolver: `0x${string}`,
      amountOut: bigint
  ): Promise<string> {
    const domain = {
      name: "T1ERC7683",
      version: "1",
      chainId: this.destinationChainId,
      verifyingContract: this.destinationChainT1Erc7683ContractAddress,
    };

    const types = {
      FillAuthorization: [
        { name: "orderId", type: "bytes32" },
        { name: "filler", type: "address" },
        { name: "amountOut", type: "uint256" },
      ],
    };
    this.logger.debug(`Types of signed properties: orderId=[${typeof orderId}] filler=[${typeof winningSolver}] amountOut=[${typeof amountOut}]`);
    this.logger.debug(`Values of signed properties: orderId=[${orderId}] filler=[${winningSolver}] amountOut=[${amountOut}]`);

    const message = {
      orderId,
      filler: winningSolver,
      amountOut,
    };

    return await this.sourceChainClient.signTypedData(domain, types, message);
  }
}
