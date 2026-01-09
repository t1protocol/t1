import { ethers } from "ethers";
import { analyzeERC7683Logs } from "./src/logAnalyzer7683.ts";

const sourceChainProvider = new ethers.JsonRpcProvider("https://base-rpc.publicnode.com");
const sourceChainErc7683Address = "0xdbA711a6c1b187479e9a5b33020E5217D0BD5A1f";

const destinationChainProvider = new ethers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");
const destinationChainErc7683Address = "0x996f3583bd967bba19694733aa7a7623e6d780eb";

const sourceChainFromBlock = 40423900;
const sourceChainLatest = 40499026;
// const sourceChainLatest    = await sourceChainProvider.getBlockNumber();

const destinationChainFromBlock = 418241010;
const destinationChainLatest = 418842847;
// const destinationChainLatest = await destinationChainProvider.getBlockNumber();

await analyzeERC7683Logs({
  sourceChainName: "Base",
  sourceChainFromBlock,
  sourceChainLatest,
  sourceChainProvider,
  sourceChainErc7683Address,
  destinationChainName: "Arbitrum",
  destinationChainFromBlock,
  destinationChainLatest,
  destinationChainProvider,
  destinationChainErc7683Address,
})
