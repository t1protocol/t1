import { ethers } from "ethers";
import { describe, expect, it } from "@jest/globals";
import { config } from "./config/tests-config";
import {waitForEvents, weiToEther} from "./common/utils";

const l1AccountManager = config.getL1AccountManager();
const l2AccountManager = config.getL2AccountManager();
const bridgeAmountUsdt = ethers.parseEther("100");

describe("Bridge USDT L1 -> L2 and L2 -> L1", () => {
  it("Bridge USDT from L1 to L2", async () => {
    const l1account = l1AccountManager.getWallet(l1AccountManager.selectWhaleAccount(0).account);

    const t1L2messengerContract = config.gett1L2messengerContract();
    const l1StandardERC20Gateway = config.getL1standardErc20gatewayContract();
    const l2StandardERC20Gateway = config.getL2standardErc20gatewayContract();
    const l1usdtContract = config.getL1usdtContract();
    const l2usdtContract = config.getL2usdtContract();
    const l1Provider = config.getL1Provider();
    const l2Provider = config.getL2Provider();

    const l1TokenBridgeAddress = await l1StandardERC20Gateway.getAddress();
    const l1TokenAddress = await l1usdtContract.getAddress();

    const allowanceTx = await l1usdtContract.connect(l1account).approve(l1TokenBridgeAddress, bridgeAmountUsdt);
    await allowanceTx.wait();

    const allowanceL1Account = await l1usdtContract.allowance(l1account.address, l1TokenBridgeAddress);
    console.log(`Current allowance of L1 account to L1 TokenBridge is [${weiToEther(allowanceL1Account.toString())}] USDT`);

    console.log("Calling the depositERC20 function on the L1 TokenBridge contract");

    const feeData = await l1Provider.getFeeData();
    const l2BlockNumberBeforeBridging = await l2Provider.getBlockNumber();

    const l1TokenBalance = await l1usdtContract.balanceOf(l1account.address);
    console.log(`Token balance of L1 account is [${weiToEther(l1TokenBalance.toString())}] USDT`);

    const initiall2TokenBalance = await l2usdtContract.balanceOf(l1account.address);
    console.log(`Token balance of L2 account before deposit is [${weiToEther(initiall2TokenBalance.toString())}] USDT`);

    const bridgeTokenTx = await l1StandardERC20Gateway
      .connect(l1account)
      ["depositERC20(address,uint256,uint256)"](l1TokenAddress, bridgeAmountUsdt, 1_000_000, {
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
      });

    await bridgeTokenTx.wait();
    console.log("L1 transaction was included. Now waiting for a L2 transaction...");

    const [relayedMessageEvent] = await waitForEvents(
      t1L2messengerContract,
      t1L2messengerContract.filters.RelayedMessage(),
      1_000,
      l2BlockNumberBeforeBridging,
      "latest",
    );
    expect(relayedMessageEvent).not.toBeNull();

    const [depositFinalized] = await waitForEvents(
        l2StandardERC20Gateway,
        l2StandardERC20Gateway.filters.FinalizeDepositERC20(),
        1_000,
        l2BlockNumberBeforeBridging,
        "latest"
    );
    expect(depositFinalized).not.toBeNull();

    const l2usdtBalanceAfterTest = await l2usdtContract.balanceOf(l1account.address);
    console.log(`Token balance of L2 account after deposit is [${weiToEther(l2usdtBalanceAfterTest.toString())}]`);

    expect(l2usdtBalanceAfterTest).toEqual(initiall2TokenBalance + bridgeAmountUsdt);
  });

  it("Bridge USDT from L2 to L1", async () => {
    const l2account = l2AccountManager.getWallet(l2AccountManager.selectWhaleAccount(0).account);

    const t1l1messengerContract = config.gett1l1messengerContract();
    const l1standardErc20gatewayContract = config.getL1standardErc20gatewayContract();
    const l2standardErc20gatewayContract = config.getL2standardErc20gatewayContract();
    const l1usdtContract = config.getL1usdtContract();
    const l2usdtContract = config.getL2usdtContract();
    const l1Provider = config.getL1Provider();
    const l2Provider = config.getL2Provider();
    const l1BlockNumberBeforeBridging = await l1Provider.getBlockNumber();

    const { maxPriorityFeePerGas: l2MaxPriorityFeePerGas, maxFeePerGas: l2MaxFeePerGas } =
      await l2Provider.getFeeData();

    const allowanceTx = await l2usdtContract.connect(l2account).approve(l2standardErc20gatewayContract, bridgeAmountUsdt);
    await allowanceTx.wait();

    const allowanceL2Account = await l2usdtContract.allowance(l2account.address, l2standardErc20gatewayContract);
    console.log(`Current allowance of L2 account to L2 TokenBridge is [${weiToEther(allowanceL2Account.toString())}] USDT`);
    console.log(`Token balance of  L2 account is [${await l2usdtContract.balanceOf(l2account)}] USDT` );

    const initialL1TokenBalance = await l1usdtContract.balanceOf(l2account.address);
    console.log(`Token balance of L1 account before withdraw is [${weiToEther(initialL1TokenBalance.toString())}] USDT`);

    const bridgeTokenTx = await l2standardErc20gatewayContract
      .connect(l2account)
      ["withdrawERC20(address,uint256,uint256)"](await l2usdtContract.getAddress(), bridgeAmountUsdt, l2account.address, {
        maxPriorityFeePerGas: l2MaxPriorityFeePerGas,
        maxFeePerGas: l2MaxFeePerGas,
      });

    await bridgeTokenTx.wait();

    console.log("L2 transaction was included. Now waiting for a L1 transaction...");

    const [relayedMessageEvent] = await waitForEvents(
        t1l1messengerContract,
        t1l1messengerContract.filters.RelayedMessage(),
        1_000,
        l1BlockNumberBeforeBridging,
        "latest",
    );
    expect(relayedMessageEvent).not.toBeNull();

    const [withdrawFinalized] = await waitForEvents(
        l1standardErc20gatewayContract,
        l1standardErc20gatewayContract.filters.FinalizeWithdrawERC20(),
        1_000,
        l1BlockNumberBeforeBridging,
        "latest"
    );
    expect(withdrawFinalized).not.toBeNull();

    const l1usdtBalanceAfterTest = await l1usdtContract.balanceOf(l2account.address);
    console.log(`Token balance of L1 account after withdraw is [${weiToEther(l1usdtBalanceAfterTest.toString())}]`);

    expect(l1usdtBalanceAfterTest).toEqual(initialL1TokenBalance + bridgeAmountUsdt);
  });
});
