import { AccountManager } from "./accounts/account-manager";

export type BaseConfig = {
  rpcUrl: URL;
  chainId: number;
  accountManager: AccountManager;
};

export type L1Config = BaseConfig & {
  l1t1messengerContractAddress: string;
  l1proxyAdminAddress: string;
  standardErc20gatewayContractAddress: string;
  l1usdtAddress: string;
};

export type L2Config = BaseConfig & {
  l2t1messengerContractAddress: string;
  standardErc20gatewayContractAddress: string;
  l2usdtAddress: string;
};

export type Config = {
  L1: L1Config;
  L2: L2Config;
};
