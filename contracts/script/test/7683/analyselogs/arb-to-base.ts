import { ethers } from "ethers";
import { analyzeERC7683Logs } from "./src/logAnalyzer7683.ts";

// -------------------- Config --------------------
const sourceChainProvider = new ethers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");
const sourceChainErc7683Address  = "0x996f3583bd967bba19694733aa7a7623e6d780eb";

const destinationChainProvider = new ethers.JsonRpcProvider("https://base-rpc.publicnode.com");
const destinationChainErc7683Address  = "0xdbA711a6c1b187479e9a5b33020E5217D0BD5A1f";

const sourceChainFromBlock = 418241010;
const sourceChainLatest    = 418842847;
// const sourceChainLatest = await sourceChainProvider.getBlockNumber();

const destinationChainFromBlock = 40423900;
const destinationChainLatest    = 40499026;
// const destinationChainLatest    = await destinationChainProvider.getBlockNumber();

await analyzeERC7683Logs({
  sourceChainName: "Arbitrum",
  sourceChainFromBlock,
  sourceChainLatest,
  sourceChainProvider,
  sourceChainErc7683Address,
  destinationChainName: "Base",
  destinationChainFromBlock,
  destinationChainLatest,
  destinationChainProvider,
  destinationChainErc7683Address,
})
