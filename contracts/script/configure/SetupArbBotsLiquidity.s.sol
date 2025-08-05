// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";

contract Setup7683BotsLiquidity is Script, DeploymentUtils {
    address private ARBITRUM_SEPOLIA_USDT_ADDR = vm.envAddress("ARBITRUM_SEPOLIA_USDT_ADDR");
    address payable private ARBITRUM_SEPOLIA_WETH_ADDR = payable(vm.envAddress("ARBITRUM_SEPOLIA_WETH_ADDR"));
    uint256 private ARBITRUM_SEPOLIA_FILL_BOT_PRIVATE_KEY = vm.envUint("ARBITRUM_SEPOLIA_FILL_BOT_PRIVATE_KEY");

    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        logStart("[START] Setup Bot liquidity");

        fundBots();
        approveContracts();

        logStart("[COMPLETE] Setup Bot liquidity");
    }

    function fundBots() private {
        uint256 FUNDER_PRIVATE_KEY = vm.envUint("FUNDER_PRIVATE_KEY");
        uint256 SETTLEMENT_BOT_PRIVATE_KEY = vm.envUint("SETTLEMENT_BOT_PRIVATE_KEY");
        uint256 SIGNER_PRIVATE_KEY = vm.envUint("SIGNER_PRIVATE_KEY");
        uint256 READ_SIGNER_PRIVATE_KEY = vm.envUint("READ_SIGNER_PRIVATE_KEY");
        uint256 READ_RESULT_PROOF_BOT_PRIVATE_KEY = vm.envUint("READ_RESULT_PROOF_BOT_PRIVATE_KEY");

        uint256 ethAmount = 90 ether;
        uint256 wethAmount = 2 ether;
        uint256 usdtAmount = 2000 * 1e6;
        address payable fillBotAddr = payable(vm.addr(ARBITRUM_SEPOLIA_FILL_BOT_PRIVATE_KEY));
        address payable settlementBotAddr = payable(vm.addr(SETTLEMENT_BOT_PRIVATE_KEY));
        address payable signerAddr = payable(vm.addr(SIGNER_PRIVATE_KEY));
        address payable readSignerAddr = payable(vm.addr(READ_SIGNER_PRIVATE_KEY));
        address payable readResultProofBotAddr = payable(vm.addr(READ_RESULT_PROOF_BOT_PRIVATE_KEY));
        // *** FUND BOTS *** //
        vm.startBroadcast(FUNDER_PRIVATE_KEY);

        // *** FILL BOT *** //
        // grant ETH to bot
        fillBotAddr.transfer(ethAmount);
        // grant WETH to bot
        WrappedEther(ARBITRUM_SEPOLIA_WETH_ADDR).transfer(fillBotAddr, wethAmount);
        // grant USDT to bot
        T1StandardERC20(ARBITRUM_SEPOLIA_USDT_ADDR).transfer(fillBotAddr, usdtAmount); // 2M USDT

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
    }

    function approveContracts() private {
        address PULL_BASED_7683_PROXY_ADDR = vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR");

        // *** ERC-20 Contract Approvals *** //
        vm.startBroadcast(ARBITRUM_SEPOLIA_FILL_BOT_PRIVATE_KEY);
        // approve L1 7683 Escrow to transfer USDT in the bot's name
        T1StandardERC20(ARBITRUM_SEPOLIA_USDT_ADDR).approve(PULL_BASED_7683_PROXY_ADDR, type(uint256).max - 1);
        // approve L1 7683 Escrow to transfer WETH in the bot's name
        WrappedEther(ARBITRUM_SEPOLIA_WETH_ADDR).approve(PULL_BASED_7683_PROXY_ADDR, type(uint256).max - 1);

        vm.stopBroadcast();
    }
}
