import { ethers } from "ethers";
import { describe, expect, it } from "@jest/globals";
import { config } from "./config/tests-config";
import { waitForEvents, etherToWei } from "./common/utils";
import { SENT_MESSAGE_EVENT_SIGNATURE } from "./common/constants";

const l1AccountManager = config.getL1AccountManager();
const l2AccountManager = config.getL2AccountManager();
const bridgeAmount = ethers.parseEther("100");
const messageSentEventMessageHashIndex = 6;

describe("Bridge USDT L1 -> L2 and L2 -> L1", () => {
  it.concurrent("Bridge a token from L1 to L2", async () => {
    const [l1whale, l2whale] = await Promise.all([
      l1AccountManager.generateAccount(),
      l2AccountManager.generateAccount(),
    ]);

    const t1l1messengerContract = config.gett1l1messengerContract();
    const t1L2messengerContract = config.gett1L2messengerContract();
    const l1StandardERC20Gateway = config.getL1standardErc20gatewayContract();
    const l2StandardERC20Gateway = config.getL2standardErc20gatewayContract();
    const l1usdtContract = config.getL1usdtContract();
    const l2usdtContract = config.getL2usdtContract();
    const l1Provider = config.getL1Provider();

    const l1TokenBridgeAddress = await l1StandardERC20Gateway.getAddress();
    const l1TokenAddress = await l1usdtContract.getAddress();

    const allowanceL1Account = await l1usdtContract.allowance(l1whale.address, l1TokenBridgeAddress);
    console.log("Current allowance of L1 account to L1 TokenBridge is :", allowanceL1Account.toString());

    console.log("Calling the bridgeToken function on the L1 TokenBridge contract");

    const feeData = await l1Provider.getFeeData();
    const nonce = await l1Provider.getTransactionCount(l1whale.address, "pending");

    const bridgeTokenTx = await l1StandardERC20Gateway
      .connect(l1whale)
      ["depositERC20(address,uint256,uint256)"](l1TokenAddress, bridgeAmount, 1_000_000, {
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
        nonce: nonce,
      });

    const bridgedTxReceipt = await bridgeTokenTx.wait();

    const sentEventLog = bridgedTxReceipt?.logs.find((log) => log.topics[0] == SENT_MESSAGE_EVENT_SIGNATURE);

    const sentMessageEvent = t1l1messengerContract.interface.decodeEventLog(
      "SentMessage",
      sentEventLog!.data,
      sentEventLog!.topics,
    );

    const l1TokenBalance = await l1usdtContract.balanceOf(l1whale.address);
    console.log("Token balance of L1 account :", l1TokenBalance.toString());

    expect(l1TokenBalance).toEqual(0n);

    const initiall2TokenBalance = await l2usdtContract.balanceOf(l2whale.address);
    console.log("Token balance of L2 account before test :", initiall2TokenBalance.toString());

    console.log("Waiting for MessageSent event on L1.");

    const messageHash = sentMessageEvent[messageSentEventMessageHashIndex];

    console.log(`Message sent on L1 : messageHash=${messageHash}`);

    console.log("Waiting for anchoring...");

    const [relayedMessageEvent] = await waitForEvents(
      t1L2messengerContract,
      t1L2messengerContract.filters.RelayedMessage(),
      1_000,
      0,
      "latest",
      // TODO filter for specific RelayedMessage event
    );
    expect(relayedMessageEvent).not.toBeNull();

    const [depositFinalized] = await waitForEvents(l2StandardERC20Gateway, l2StandardERC20Gateway.filters.FinalizeDepositERC20());
    expect(depositFinalized).not.toBeNull();

    console.log(`Message relayed on L2 : ${JSON.stringify(relayedMessageEvent)}.`);
    console.log(`Token deposited on  L2 : ${JSON.stringify(depositFinalized)}.`);

    console.log("Verify the token balance on L2");

    const l2usdtBalanceAfterTest = await l2usdtContract.balanceOf(l2whale.address);
    console.log("Token balance of L2 account :", l2usdtBalanceAfterTest.toString());

    expect(l2usdtBalanceAfterTest).toEqual(initiall2TokenBalance + bridgeAmount);
  });

  // it.concurrent("Bridge a token from L2 to L1", async () => {
  //   const [l1Account, l2Account] = await Promise.all([
  //     l1AccountManager.generateAccount(),
  //     l2AccountManager.generateAccount(),
  //   ]);
  //
  //   const lineaRollup = config.gett1l1messengerContract();
  //   const l2MessageService = config.gett1L2messengerContract();
  //   const l1TokenBridge = config.getL1standardErc20gatewayContract();
  //   const l2TokenBridge = config.getL2standardErc20gatewayContract();
  //   const l2Token = config.getL2usdtContract();
  //   const l2Provider = config.getL2Provider();
  //
  //   const { maxPriorityFeePerGas: l2MaxPriorityFeePerGas, maxFeePerGas: l2MaxFeePerGas } =
  //     await l2Provider.getFeeData();
  //   let nonce = await l2Provider.getTransactionCount(l2Account.address, "pending");
  //
  //   await Promise.all([
  //     (
  //       await l2Token.connect(l2Account).mint(l2Account.address, bridgeAmount, {
  //         nonce: nonce,
  //         maxPriorityFeePerGas: l2MaxPriorityFeePerGas,
  //         maxFeePerGas: l2MaxFeePerGas,
  //       })
  //     ).wait(),
  //     (
  //       await l2Token.connect(l2Account).approve(l2TokenBridge.getAddress(), ethers.parseEther("100"), {
  //         maxPriorityFeePerGas: l2MaxPriorityFeePerGas,
  //         maxFeePerGas: l2MaxFeePerGas,
  //         nonce: nonce + 1,
  //       })
  //     ).wait(),
  //   ]);
  //
  //   const allowanceL2Account = await l2Token.allowance(l2Account.address, l2TokenBridge.getAddress());
  //   console.log("Current allowance of L2 account to L2 TokenBridge is :", allowanceL2Account.toString());
  //   console.log("Current balance of  L2 account is :", await l2Token.balanceOf(l2Account));
  //
  //   console.log("Calling the bridgeToken function on the L2 TokenBridge contract");
  //
  //   nonce = await l2Provider.getTransactionCount(l2Account.address, "pending");
  //
  //   const bridgeTokenTx = await l2TokenBridge
  //     .connect(l2Account)
  //     .bridgeToken(await l2Token.getAddress(), bridgeAmount, l1Account.address, {
  //       value: etherToWei("0.01"),
  //       maxPriorityFeePerGas: l2MaxPriorityFeePerGas,
  //       maxFeePerGas: l2MaxFeePerGas,
  //       nonce: nonce,
  //     });
  //
  //   const receipt = await bridgeTokenTx.wait();
  //   const sentEventLog = receipt?.logs.find((log) => log.topics[0] == SENT_MESSAGE_EVENT_SIGNATURE);
  //
  //   const messageSentEvent = l2MessageService.interface.decodeEventLog(
  //     "MessageSent",
  //     sentEventLog!.data,
  //     sentEventLog!.topics,
  //   );
  //   const messageHash = messageSentEvent[messageSentEventMessageHashIndex];
  //
  //   console.log("Waiting for L1 MessageClaimed event.");
  //
  //   const [claimedEvent] = await waitForEvents(lineaRollup, lineaRollup.filters.MessageClaimed(messageHash));
  //   expect(claimedEvent).not.toBeNull();
  //
  //   console.log(`Message claimed on L1 : ${JSON.stringify(claimedEvent)}`);
  //
  //   const [newTokenDeployed] = await waitForEvents(l1TokenBridge, l1TokenBridge.filters.NewTokenDeployed());
  //   expect(newTokenDeployed).not.toBeNull();
  //
  //   const l1BridgedToken = config.getL1BridgedTokenContract(newTokenDeployed.args.bridgedToken);
  //
  //   console.log("Verify the token balance on L1");
  //
  //   const l1BridgedTokenBalance = await l1BridgedToken.balanceOf(l1Account.address);
  //   console.log("Token balance of L1 account :", l1BridgedTokenBalance.toString());
  //
  //   expect(l1BridgedTokenBalance).toEqual(bridgeAmount);
  // });
});
