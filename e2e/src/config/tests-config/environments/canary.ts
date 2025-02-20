import { ethers } from "ethers";
import { EnvironmentBasedAccountManager } from "../accounts/environment-based-account-manager";
import { Config } from "../types";
import Account from "../accounts/account";

const L1_RPC_URL = new URL(`https://sepolia.infura.io/v3/${process.env.INFURA_PROJECT_ID}`);
const L2_RPC_URL = new URL("https://rpc.devnet.t1protocol.com");
const L1_CHAIN_ID = 11155111;
const L2_CHAIN_ID = 3151908;

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
    l1t1messengerContractAddress: "0x30622442E5421C49A8F89e871Bf37D55f8755B0E",
    l1proxyAdminAddress: "0x7f17cFe7bb890b222557Ee0d5f69DD87C6B5d17a",
    standardErc20gatewayContractAddress: "0x840e8C42dF441df6431343F6FCc18869fDC9C917",
    l1usdtAddress: "0x30E9b6B0d161cBd5Ff8cf904Ff4FA43Ce66AC346",
    accountManager: new EnvironmentBasedAccountManager(
      new ethers.JsonRpcProvider(L1_RPC_URL.toString()),
      L1_WHALE_ACCOUNTS,
      L1_CHAIN_ID,
    ),
  },
  L2: {
    rpcUrl: L2_RPC_URL,
    chainId: L2_CHAIN_ID,
    l2t1messengerContractAddress: "0x30622442E5421C49A8F89e871Bf37D55f8755B0E",
    standardErc20gatewayContractAddress: "0x840e8C42dF441df6431343F6FCc18869fDC9C917",
    l2usdtAddress: "",
    accountManager: new EnvironmentBasedAccountManager(
      new ethers.JsonRpcProvider(L2_RPC_URL.toString()),
      L2_WHALE_ACCOUNTS,
      L2_CHAIN_ID,
    ),
  },
};

export default config;
