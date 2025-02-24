import { ethers } from "ethers";
import { EnvironmentBasedAccountManager } from "../accounts/environment-based-account-manager";
import { Config } from "../types";
import Account from "../accounts/account";
import * as dotenv from "dotenv";

dotenv.config();

const L1_RPC_URL = new URL(process.env.L1_RPC_URL);
const L2_RPC_URL = new URL(process.env.L2_RPC_URL);
const L1_CHAIN_ID: number = +process.env.L1_CHAIN_ID;
const L2_CHAIN_ID: number = +process.env.L2_CHAIN_ID;

const L1_WHALE_ACCOUNTS_PRIVATE_KEYS: string[] = process.env.L1_WHALE_ACCOUNTS_PRIVATE_KEYS?.split(",") ?? [];
const L2_WHALE_ACCOUNTS_PRIVATE_KEYS: string[] = process.env.L2_WHALE_ACCOUNTS_PRIVATE_KEYS?.split(",") ?? [];
const L1_WHALE_ACCOUNTS_ADDRESSES: string[] = process.env.L1_WHALE_ACCOUNTS_ADDRESSES?.split(",") ?? [];
const L2_WHALE_ACCOUNTS_ADDRESSES: string[] = process.env.L2_WHALE_ACCOUNTS_ADDRESSES?.split(",") ?? [];

const L1_WHALE_ACCOUNTS: Account[] = L1_WHALE_ACCOUNTS_PRIVATE_KEYS.map((privateKey, index) => {
  return new Account(privateKey, L1_WHALE_ACCOUNTS_ADDRESSES[index]);
});

const L2_WHALE_ACCOUNTS: Account[] = L2_WHALE_ACCOUNTS_PRIVATE_KEYS.map((privateKey, index) => {
  return new Account(privateKey, L2_WHALE_ACCOUNTS_ADDRESSES[index]);
});

const config: Config = {
  L1: {
    rpcUrl: L1_RPC_URL,
    chainId: L1_CHAIN_ID,
    l1t1messengerContractAddress: process.env.L1_T1_MESSENGER_ADDRESS,
    standardErc20gatewayContractAddress: process.env.L1_STANDARD_ERC20_GATEWAY_ADDRESS,
    l1usdtAddress: process.env.L1_USDT_ADDRESS,
    accountManager: new EnvironmentBasedAccountManager(
      new ethers.JsonRpcProvider(L1_RPC_URL.toString()),
      L1_WHALE_ACCOUNTS,
      L1_CHAIN_ID,
    ),
  },
  L2: {
    rpcUrl: L2_RPC_URL,
    chainId: L2_CHAIN_ID,
    l2t1messengerContractAddress: process.env.L2_T1_MESSENGER_ADDRESS,
    standardErc20gatewayContractAddress: process.env.L2_STANDARD_ERC20_GATEWAY_ADDRESS,
    l2usdtAddress: process.env.L2_USDT_ADDRESS,
    accountManager: new EnvironmentBasedAccountManager(
      new ethers.JsonRpcProvider(L2_RPC_URL.toString()),
      L2_WHALE_ACCOUNTS,
      L2_CHAIN_ID,
    ),
  },
};

export default config;
