import { ethers } from "ethers";
import { analyzeERC7683Logs } from "./src/logAnalyzer7683.ts";

const baseProvider = new ethers.JsonRpcProvider("https://base-rpc.publicnode.com");
const baseErc7683Address = "0xdbA711a6c1b187479e9a5b33020E5217D0BD5A1f";

const destinationChainProvider = new ethers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");
const destinationChainErc7683Address = "0x996f3583bd967bba19694733aa7a7623e6d780eb";

const baseFromBlock = 40423900;
const baseToBlock = 40499026;
// const baseToBlock    = await baseProvider.getBlockNumber();

const arbitrumFromBlock = 418241010;
const arbitrumToBlock = 418842847;
// const arbitrumToBlock = await destinationChainProvider.getBlockNumber();

await analyzeERC7683Logs({
  sourceChainName: "Base",
  sourceChainFromBlock: baseFromBlock,
  sourceChainLatest: baseToBlock,
  sourceChainProvider: baseProvider,
  sourceChainErc7683Address: baseErc7683Address,
  destinationChainName: "Arbitrum",
  destinationChainFromBlock: arbitrumFromBlock,
  destinationChainLatest: arbitrumToBlock,
  destinationChainProvider,
  destinationChainErc7683Address,
})
