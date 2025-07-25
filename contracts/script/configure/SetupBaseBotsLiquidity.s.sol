// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";

contract Setup7683BotsLiquidity is Script, DeploymentUtils {
    uint256 private FUNDER_PRIVATE_KEY = vm.envUint("FUNDER_PRIVATE_KEY");
    uint256 private FILL_BOT_PRIVATE_KEY = vm.envUint("L2_7683_FILL_BOT_PRIVATE_KEY");
    uint256 private SETTLEMENT_BOT_PRIVATE_KEY = vm.envUint("SETTLEMENT_BOT_PRIVATE_KEY");
    uint256 private SIGNER_PRIVATE_KEY = vm.envUint("SIGNER_PRIVATE_KEY");
    uint256 private READ_SIGNER_PRIVATE_KEY = vm.envUint("READ_SIGNER_PRIVATE_KEY");
    uint256 private READ_RESULT_PROOF_BOT_PRIVATE_KEY = vm.envUint("READ_RESULT_PROOF_BOT_PRIVATE_KEY");

    address payable private WETH_ADDR = payable(vm.envAddress("L2_WETH_ADDR"));
    address private USDT_ADDR = vm.envAddress("L2_USDT_ADDR");
    address private PULL_BASED_7683_PROXY_ADDR = vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR");

    function run() external {
        uint256 ethAmount = 90 ether;
        uint256 wethAmount = 2 ether;
        uint256 usdtAmount = 2000 * 1e6;
        address payable fillBotAddr = payable(vm.addr(FILL_BOT_PRIVATE_KEY));
        address payable settlementBotAddr = payable(vm.addr(SETTLEMENT_BOT_PRIVATE_KEY));
        address payable signerAddr = payable(vm.addr(SIGNER_PRIVATE_KEY));
        address payable readSignerAddr = payable(vm.addr(READ_SIGNER_PRIVATE_KEY));
        address payable readResultProofBotAddr = payable(vm.addr(READ_RESULT_PROOF_BOT_PRIVATE_KEY));

        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        logStart("[START] Setup Bot liquidity");

        // *** FUND BOTS *** //
        vm.startBroadcast(FUNDER_PRIVATE_KEY);

        // *** FILL BOT *** //
        // grant ETH to bot
        fillBotAddr.transfer(ethAmount);
        // grant WETH to bot
        WrappedEther(WETH_ADDR).transfer(fillBotAddr, wethAmount);
        // grant USDT to bot
        T1StandardERC20(USDT_ADDR).transfer(fillBotAddr, usdtAmount); // 2M USDT

        // *** SETTLEMENT BOT *** //
        // grant ETH to bot
        settlementBotAddr.transfer(5 ether);

        // *** SIGNER *** //
        // grant ETH to bot
        signerAddr.transfer(1 ether);

        // *** READ SIGNER *** //
        // grant ETH to bot
        readSignerAddr.transfer(1 ether);

        // *** READ RESULT PROOF BOT *** //
        // grant ETH to bot
        readResultProofBotAddr.transfer(1 ether);

        vm.stopBroadcast();

        // *** ERC-20 Contract Approvals *** //
        vm.startBroadcast(FILL_BOT_PRIVATE_KEY);
        // approve L1 7683 Escrow to transfer USDT in the bot's name
        T1StandardERC20(USDT_ADDR).approve(
            PULL_BASED_7683_PROXY_ADDR,
            115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935
        );
        // approve L1 7683 Escrow to transfer WETH in the bot's name
        WrappedEther(WETH_ADDR).approve(
            PULL_BASED_7683_PROXY_ADDR,
            115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935
        );

        vm.stopBroadcast();

        logStart("[COMPLETE] Setup Bot liquidity");
    }
}
