import {
  decodeAbiParameters,
  parseEventLogs,
  trim,
  type AbiEvent,
  type Log,
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
const RECONNECT_DELAY_MS = 5000;
const HEALTHCHECK_INTERVAL_MS = 60_000; // Log health every minute
const POLLING_BACKUP_INTERVAL_MS = 30_000; // Poll every 30 seconds as backup
const PAGERDUTY_EVENTS_URL = "https://events.pagerduty.com/v2/enqueue";

export class ViemIntentObserver {
  private logger: WinstonLogger;
  private lastProcessedBlock: bigint = 0n;
  private isRecovering: boolean = false;
  private unwatch: (() => void) | null = null;
  private startedAt: Date | null = null;
  private eventsProcessed: number = 0;
  private healthcheckInterval: ReturnType<typeof setInterval> | null = null;
  private pollingInterval: ReturnType<typeof setInterval> | null = null;
  private processedEventIds: Set<string> = new Set();

  constructor(
    private readonly sourceChainClient: BlockchainClient,
    private readonly sourceChainT1Erc7683ContractAddress: `0x${string}`,
    private readonly auctionService: AuctionService,
    private readonly apiServer: AuctionApiServer,
    private readonly destinationChainId: number,
    private readonly destinationChainT1Erc7683ContractAddress: `0x${string}`,
    private readonly auctionPollingInterval: number = 500,
    private readonly fromBlock: bigint | null,
    private readonly pagerDutyIntegrationKey: string | null = null
  ) {
    this.logger = new WinstonLogger(
      `${ViemIntentObserver.name}[${this.sourceChainClient.publicClient.chain.name}]`
    );
  }

  public async start() {
    const chainName = this.sourceChainClient.publicClient.chain.name;
    this.startedAt = new Date();

    this.logger.info(`🚀 Starting ViemIntentObserver on ${chainName}`);

    // Initialize lastProcessedBlock to current block if not doing historical fetch
    if (this.fromBlock === null) {
      this.lastProcessedBlock = await this.sourceChainClient.publicClient.getBlockNumber();
      this.logger.info(`Initialized lastProcessedBlock to ${this.lastProcessedBlock}`);
    } else {
      await this.fetchHistoricalLogs();
    }

    this.startWatching();
    this.startHealthcheck();
    this.startPollingBackup();
  }

  private startHealthcheck() {
    const chainName = this.sourceChainClient.publicClient.chain.name;

    this.healthcheckInterval = setInterval(async () => {
      const uptime = this.startedAt
        ? Math.floor((Date.now() - this.startedAt.getTime()) / 1000)
        : 0;
      const uptimeStr = `${Math.floor(uptime / 3600)}h ${Math.floor((uptime % 3600) / 60)}m`;

      try {
        const currentBlock = await this.sourceChainClient.publicClient.getBlockNumber();
        const blocksBehind = currentBlock - this.lastProcessedBlock;

        this.logger.info(
          `💚 HEALTHCHECK [${chainName}] | uptime=${uptimeStr} | lastBlock=${this.lastProcessedBlock} | currentBlock=${currentBlock} | behind=${blocksBehind} | eventsProcessed=${this.eventsProcessed} | recovering=${this.isRecovering}`
        );

        // Warn if too far behind
        if (blocksBehind > 1000n) {
          this.logger.warn(
            `⚠️ ${chainName} is ${blocksBehind} blocks behind! May have missed events.`
          );
        }
      } catch (e) {
        this.logger.error(`Healthcheck failed on ${chainName}: ${e}`);
      }
    }, HEALTHCHECK_INTERVAL_MS);
  }

  public stop() {
    if (this.unwatch) {
      this.unwatch();
      this.unwatch = null;
    }
    if (this.healthcheckInterval) {
      clearInterval(this.healthcheckInterval);
      this.healthcheckInterval = null;
    }
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
      this.pollingInterval = null;
    }
    this.logger.info(`Stopped ViemIntentObserver`);
  }

  private startPollingBackup() {
    const chainName = this.sourceChainClient.publicClient.chain.name;

    this.logger.info(`Starting polling backup on ${chainName} (every ${POLLING_BACKUP_INTERVAL_MS}ms)`);

    this.pollingInterval = setInterval(async () => {
      try {
        const currentBlock = await this.sourceChainClient.publicClient.getBlockNumber();

        // Only poll if we have a valid lastProcessedBlock and are potentially behind
        if (this.lastProcessedBlock > 0n && currentBlock > this.lastProcessedBlock) {
          const fromBlock = this.lastProcessedBlock + 1n;

          this.logger.debug(`Polling backup: checking blocks ${fromBlock} to ${currentBlock}`);

          const logs = await this.sourceChainClient.publicClient.getLogs({
            address: this.sourceChainT1Erc7683ContractAddress,
            event: OPEN_INTENT_ABI_EVENT as AbiEvent,
            fromBlock,
            toBlock: currentBlock,
          });

          if (logs.length > 0) {
            this.logger.info(`🔍 Polling backup found ${logs.length} events in blocks ${fromBlock}-${currentBlock}`);

            // Update lastProcessedBlock
            const maxBlock = logs.reduce(
              (max, log) => (log.blockNumber > max ? log.blockNumber : max),
              0n
            );
            this.lastProcessedBlock = maxBlock;

            await this.processIntentLogs(logs as unknown as WatchEventOnLogsParameter);
          } else {
            // Even if no events, update lastProcessedBlock so we don't re-scan
            this.lastProcessedBlock = currentBlock;
          }
        }
      } catch (e) {
        this.logger.error(`Polling backup failed on ${chainName}: ${e}`);
      }
    }, POLLING_BACKUP_INTERVAL_MS);
  }

  private startWatching() {
    const chainName = this.sourceChainClient.publicClient.chain.name;

    this.unwatch = this.sourceChainClient.publicClient.watchEvent({
      address: this.sourceChainT1Erc7683ContractAddress,
      event: OPEN_INTENT_ABI_EVENT,
      onLogs: (logs) => {
        // Track the last processed block for recovery
        if (logs.length > 0) {
          const maxBlock = logs.reduce(
            (max, log) => (log.blockNumber > max ? log.blockNumber : max),
            0n
          );
          this.lastProcessedBlock = maxBlock;
        }
        this.processIntentLogs(logs);
      },
      onError: (error: Error) => this.handleWatchError(error),
    });

    this.logger.info(
      `Watching for Open Intent events on chain [${chainName}] and contract [${this.sourceChainT1Erc7683ContractAddress}]`
    );
  }

  private async handleWatchError(error: Error) {
    const chainName = this.sourceChainClient.publicClient.chain.name;

    this.logger.error(
      `🚨 WEBSOCKET DROPPED on ${chainName}! Error: ${error.message}. Last processed block: ${this.lastProcessedBlock}`
    );

    // Fire PagerDuty alert
    await this.sendPagerDutyAlert(
      `WebSocket dropped on ${chainName}`,
      `Error: ${error.message}. Last processed block: ${this.lastProcessedBlock}`,
      `ws-drop-${chainName}`
    );

    if (this.isRecovering) {
      this.logger.warn(`Already recovering, skipping duplicate recovery attempt`);
      return;
    }

    this.isRecovering = true;

    try {
      if (this.unwatch) {
        this.unwatch();
        this.unwatch = null;
      }

      this.logger.info(`Waiting ${RECONNECT_DELAY_MS}ms before recovery...`);
      await new Promise((resolve) => setTimeout(resolve, RECONNECT_DELAY_MS));

      if (this.lastProcessedBlock > 0n) {
        this.logger.info(
          `🔄 Recovering missed events from block ${this.lastProcessedBlock + 1n} on ${chainName}`
        );
        await this.fetchHistoricalLogsFromBlock(this.lastProcessedBlock + 1n);
      }

      this.logger.info(`✅ Restarting event watcher on ${chainName}`);
      this.startWatching();

      this.logger.info(
        `✅ Recovery complete on ${chainName}. Resumed watching from block ${this.lastProcessedBlock}`
      );
    } catch (recoveryError) {
      this.logger.error(
        `🚨 RECOVERY FAILED on ${chainName}: ${recoveryError}. Will retry in ${RECONNECT_DELAY_MS}ms`
      );

      // Fire PagerDuty alert for recovery failure
      await this.sendPagerDutyAlert(
        `WebSocket recovery FAILED on ${chainName}`,
        `Recovery error: ${recoveryError}. Will retry in ${RECONNECT_DELAY_MS}ms`,
        `ws-recovery-fail-${chainName}`
      );

      // Schedule another recovery attempt
      setTimeout(() => {
        this.isRecovering = false;
        this.handleWatchError(error);
      }, RECONNECT_DELAY_MS);
      return;
    }

    this.isRecovering = false;
  }

  private async fetchHistoricalLogs() {
    if (this.fromBlock === null) return;
    await this.fetchHistoricalLogsFromBlock(this.fromBlock);
  }

  private async fetchHistoricalLogsFromBlock(startBlock: bigint) {
    const chainName = this.sourceChainClient.publicClient.chain.name;
    const currentBlock = await this.sourceChainClient.publicClient.getBlockNumber();

    this.logger.info(
      `Fetching historical logs on ${chainName} from block ${startBlock} to ${currentBlock}`
    );

    let fromBlock = startBlock;
    let totalLogsFound = 0;

    while (fromBlock <= currentBlock) {
      const toBlock = fromBlock + HISTORICAL_BLOCK_CHUNK_SIZE - 1n > currentBlock
        ? currentBlock
        : fromBlock + HISTORICAL_BLOCK_CHUNK_SIZE - 1n;

      this.logger.debug(`Fetching logs from block ${fromBlock} to ${toBlock}`);

      const logs = await this.sourceChainClient.publicClient.getLogs({
        address: this.sourceChainT1Erc7683ContractAddress,
        event: OPEN_INTENT_ABI_EVENT as AbiEvent,
        fromBlock,
        toBlock,
      });

      if (logs.length > 0) {
        totalLogsFound += logs.length;
        this.logger.info(`Found ${logs.length} historical logs in blocks ${fromBlock}-${toBlock}`);

        const maxBlock = logs.reduce(
          (max, log) => (log.blockNumber > max ? log.blockNumber : max),
          0n
        );
        this.lastProcessedBlock = maxBlock;

        await this.processIntentLogs(logs as unknown as WatchEventOnLogsParameter);
      }

      fromBlock = toBlock + 1n;
    }

    this.lastProcessedBlock = currentBlock;

    this.logger.info(
      `Finished fetching historical logs on ${chainName}. Found ${totalLogsFound} events, caught up to block ${currentBlock}`
    );
  }

  private async processIntentLogs(logs: WatchEventOnLogsParameter) {
    const parsedLogs = parseEventLogs({
      abi: [OPEN_INTENT_ABI_EVENT],
      logs,
    });

    // Filter out already-processed events (dedup between WebSocket and polling)
    const newLogs: { order: typeof parsedLogs[number]; rawLog: Log }[] = [];
    for (let i = 0; i < parsedLogs.length; i++) {
      const rawLog = logs[i];
      const order = parsedLogs[i];
      if (!rawLog || !order) continue;

      const eventId = `${rawLog.transactionHash}-${rawLog.logIndex}`;

      if (this.processedEventIds.has(eventId)) {
        this.logger.debug(`Skipping already-processed event: ${eventId}`);
        continue;
      }

      this.processedEventIds.add(eventId);
      newLogs.push({ order, rawLog: rawLog as Log });

      // Limit memory usage: keep only last 10k event IDs
      if (this.processedEventIds.size > 10000) {
        const firstId = this.processedEventIds.values().next().value;
        if (firstId) this.processedEventIds.delete(firstId);
      }
    }

    if (newLogs.length === 0) {
      return;
    }

    this.eventsProcessed += newLogs.length;
    this.logger.info(`Intent was Open-ed! (${newLogs.length} new event(s), total processed: ${this.eventsProcessed})`);

    for (const { order, rawLog } of newLogs) {
      // Convert raw log to eth_getLogs hex format for tokka-filler
      const openEvent: OpenEventLog = {
        address: rawLog.address,
        topics: rawLog.topics as string[],
        data: rawLog.data,
        blockNumber: `0x${rawLog.blockNumber!.toString(16)}`,
        transactionHash: rawLog.transactionHash!,
        transactionIndex: `0x${rawLog.transactionIndex!.toString(16)}`,
        blockHash: rawLog.blockHash!,
        logIndex: `0x${rawLog.logIndex!.toString(16)}`,
        removed: rawLog.removed,
      };

      for (const fillInstruction of order.args.resolvedOrder.fillInstructions) {
        const [decodedOrder] = decodeAbiParameters(
          ORDER_DATA_ABI_PARAMETERS_WRAPPED_IN_TUPLE,
          fillInstruction.originData
        );

        const orderData = decodedOrder as OrderData;

        await this.runAuctionAndNotifySolver(
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
          order.args.orderId as `0x${string}`,
          openEvent
        );
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

  private async sendPagerDutyAlert(
    summary: string,
    details: string,
    dedupKey: string
  ): Promise<void> {
    if (!this.pagerDutyIntegrationKey) {
      this.logger.debug("PagerDuty integration key not configured, skipping alert");
      return;
    }

    try {
      const response = await fetch(PAGERDUTY_EVENTS_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          routing_key: this.pagerDutyIntegrationKey,
          event_action: "trigger",
          dedup_key: `sealed-bid-auction-${dedupKey}`,
          payload: {
            summary,
            source: "sealed-bid-auction",
            severity: "critical",
            custom_details: { details },
          },
        }),
      });

      if (!response.ok) {
        this.logger.error(`PagerDuty alert failed: ${response.status} ${response.statusText}`);
      } else {
        this.logger.info(`PagerDuty alert sent: ${summary}`);
      }
    } catch (e) {
      this.logger.error(`Failed to send PagerDuty alert: ${e}`);
    }
  }
}
