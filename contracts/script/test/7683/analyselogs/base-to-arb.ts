import { ethers } from "ethers";
import { analyzeERC7683Logs } from "./src/logAnalyzer7683.ts";

const baseProvider = new ethers.JsonRpcProvider("https://base-rpc.publicnode.com");
const baseErc7683Address = "0xdbA711a6c1b187479e9a5b33020E5217D0BD5A1f";

const destinationChainProvider = new ethers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");
const destinationChainErc7683Address = "0x996f3583bd967bba19694733aa7a7623e6d780eb";

const baseToBlock = 40804426;
const baseFromBlock = baseToBlock - (1800 * 4);
// const baseToBlock    = await baseProvider.getBlockNumber();

const arbitrumToBlock = 421286660;
const arbitrumFromBlock = arbitrumToBlock - (14400 * 4);
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
