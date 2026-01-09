import { ethers } from "ethers";
import { analyzeERC7683Logs } from "./src/logAnalyzer7683.ts";

const arbitrumProvider = new ethers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");
const arbitrumErc7683Address = "0x996f3583bd967bba19694733aa7a7623e6d780eb";

const baseProvider = new ethers.JsonRpcProvider("https://base-rpc.publicnode.com");
const baseErc7683Address = "0xdbA711a6c1b187479e9a5b33020E5217D0BD5A1f";

const arbitrumFromBlock = 417132015;
const arbitrumToBlock = 418842847;
// const sourceChainLatest = await sourceChainProvider.getBlockNumber();

const baseFromBlock = 40423900;
const baseToBlock = 40499026;
// const destinationChainLatest    = await destinationChainProvider.getBlockNumber();

await analyzeERC7683Logs({
  sourceChainName: "Arbitrum",
  sourceChainFromBlock: arbitrumFromBlock,
  sourceChainLatest: arbitrumToBlock,
  sourceChainProvider: arbitrumProvider,
  sourceChainErc7683Address: arbitrumErc7683Address,
  destinationChainName: "Base",
  destinationChainFromBlock: baseFromBlock,
  destinationChainLatest: baseToBlock,
  destinationChainProvider: baseProvider,
  destinationChainErc7683Address: baseErc7683Address,
})
