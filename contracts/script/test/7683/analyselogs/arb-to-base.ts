import { ethers } from "ethers";
import { analyzeERC7683Logs } from "./src/logAnalyzer7683.ts";
import { ONE_DAY_IN_ARBITRUM_BLOCKS, ONE_DAY_IN_BASE_BLOCKS } from "./src/common.ts";

const arbitrumProvider = new ethers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");
const arbitrumErc7683Address = "0x996f3583bd967bba19694733aa7a7623e6d780eb";

const baseProvider = new ethers.JsonRpcProvider("https://base-rpc.publicnode.com");
const baseErc7683Address = "0xdbA711a6c1b187479e9a5b33020E5217D0BD5A1f";

const arbitrumToBlock = 420188164;
const arbitrumFromBlock = arbitrumToBlock - 7 * ONE_DAY_IN_ARBITRUM_BLOCKS ;
// const sourceChainLatest = await sourceChainProvider.getBlockNumber();

const baseToBlock = 40667169;
const baseFromBlock = baseToBlock - 7 * ONE_DAY_IN_BASE_BLOCKS;
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
