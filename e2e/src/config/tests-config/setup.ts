import { AbstractSigner, JsonRpcProvider, Wallet } from "ethers";
import { Config } from "./types";
import {
  L2T1Messenger,
  L2T1Messenger__factory,
  L1T1Messenger,
  L1T1Messenger__factory,
  IERC20,
  IERC20__factory,
  L1StandardERC20Gateway,
  L1StandardERC20Gateway__factory,
  L2StandardERC20Gateway,
  L2StandardERC20Gateway__factory,
} from "../../typechain";
import { AccountManager } from "./accounts/account-manager";

export default class TestSetup {
  constructor(private readonly config: Config) {}

  public getL1Provider(): JsonRpcProvider {
    return new JsonRpcProvider(this.config.L1.rpcUrl.toString());
  }

  public getL2Provider(): JsonRpcProvider {
    return new JsonRpcProvider(this.config.L2.rpcUrl.toString());
  }

  public getL1ChainId(): number {
    return this.config.L1.chainId;
  }

  public getL2ChainId(): number {
    return this.config.L2.chainId;
  }

  public gett1l1messengerContract(signer?: AbstractSigner): L1T1Messenger {
    const l1T1Messenger: L1T1Messenger = L1T1Messenger__factory.connect(
      this.config.L1.l1t1messengerContractAddress,
      this.getL1Provider(),
    );

    if (signer) {
      return l1T1Messenger.connect(signer);
    }

    return l1T1Messenger;
  }

  public gett1L2messengerContract(signer?: Wallet): L2T1Messenger {
    const l2MessageService: L2T1Messenger = L2T1Messenger__factory.connect(
      this.config.L2.l2t1messengerContractAddress,
      this.getL2Provider(),
    );

    if (signer) {
      return l2MessageService.connect(signer);
    }

    return l2MessageService;
  }

  public getL1standardErc20gatewayContract(signer?: Wallet): L1StandardERC20Gateway {
    const l1TokenBridge: L1StandardERC20Gateway = L1StandardERC20Gateway__factory.connect(
      this.config.L1.standardErc20gatewayContractAddress,
      this.getL1Provider(),
    );

    if (signer) {
      return l1TokenBridge.connect(signer);
    }

    return l1TokenBridge;
  }

  public getL2standardErc20gatewayContract(signer?: Wallet): L2StandardERC20Gateway {
    const l2TokenBridge: L2StandardERC20Gateway = L2StandardERC20Gateway__factory.connect(
      this.config.L2.standardErc20gatewayContractAddress,
      this.getL2Provider(),
    );

    if (signer) {
      return l2TokenBridge.connect(signer);
    }

    return l2TokenBridge;
  }

  public getL1usdtContract(signer?: Wallet): IERC20 {
    const l1Token: IERC20 = IERC20__factory.connect(this.config.L1.l1usdtAddress, this.getL1Provider());

    if (signer) {
      return l1Token.connect(signer);
    }

    return l1Token;
  }

  public getL2usdtContract(signer?: Wallet): IERC20 {
    const l2Token: IERC20 = IERC20__factory.connect(this.config.L2.l2usdtAddress, this.getL2Provider());

    if (signer) {
      return l2Token.connect(signer);
    }

    return l2Token;
  }

  public getL1AccountManager(): AccountManager {
    return this.config.L1.accountManager;
  }

  public getL2AccountManager(): AccountManager {
    return this.config.L2.accountManager;
  }
}
