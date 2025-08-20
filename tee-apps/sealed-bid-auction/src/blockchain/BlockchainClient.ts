import { type Chain, createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";

export class BlockchainClient {
  private _publicClient;
  private _walletClient;

  public constructor(
    rpcUrl: string,
    chain: Chain,
    pollingInterval: number,
    private readonly signerKey?: `0x${string}`
  ) {
    this._publicClient = createPublicClient({
      chain,
      transport: http(rpcUrl),
      pollingInterval,
    });

    if (signerKey) {
      const account = privateKeyToAccount(signerKey);

      this._walletClient = createWalletClient({
        account,
        chain: chain,
        transport: http(rpcUrl),
      });
    }
  }

  public get publicClient() {
    return this._publicClient;
  }

  public get walletClient() {
    if (!this._walletClient) {
      throw new Error("Wallet client not initialised!");
    }

    return this._walletClient;
  }

  public async signMessage(message: string): Promise<`0x${string}`> {
    if (!this.signerKey) {
      throw new Error("Signer key not initialised!");
    }

    const account = privateKeyToAccount(this.signerKey);

    return await account.signMessage({
      message,
    });
  }

  public async signTypedData(
    domain: Record<string, any>,
    types: Record<string, any>,
    message: Record<string, any>
  ): Promise<`0x${string}`> {
    if (!this.signerKey) {
      throw new Error("Signer key not initialised!");
    }

    const account = privateKeyToAccount(this.signerKey);

    const primaryType = Object.keys(types)[0];
    if (!primaryType) {
      throw new Error("No types provided for EIP-712 signing");
    }

    return await account.signTypedData({
      domain,
      types,
      primaryType,
      message,
    });
  }
}
