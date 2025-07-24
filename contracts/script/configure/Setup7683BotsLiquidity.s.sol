// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";
import { IL1ERC20Gateway } from "../../src/L1/gateways/IL1ERC20Gateway.sol";

import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";
import { Usdt } from "../deploy/DeployL1Usdt.s.sol";

contract Setup7683BotsLiquidity is Script, DeploymentUtils {
    uint256 private L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
    uint256 private L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
    uint256 private L1_7683_BOT_PRIVATE_KEY = vm.envUint("L1_7683_FILL_BOT_PRIVATE_KEY");
    uint256 private L2_7683_BOT_PRIVATE_KEY = vm.envUint("L2_7683_FILL_BOT_PRIVATE_KEY");

    address payable private L1_WETH_ADDR = payable(vm.envAddress("L1_WETH_ADDR"));
    address private L1_USDT_ADDR = vm.envAddress("L1_USDT_ADDR");
    address payable private L2_WETH_ADDR = payable(vm.envAddress("L2_WETH_ADDR"));
    address private L2_USDT_ADDR = vm.envAddress("L2_USDT_ADDR");
    //    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address private L1_T1_PULL_BASED_7683_PROXY_ADDR = vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR");
    address private L2_T1_PULL_BASED_7683_PROXY_ADDR = vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR");

    function run() external {
        uint256 gasLimit = 1_000_000;
        uint256 ethAmount = 2 ether;
        uint256 wethAmount = 2_000_000_000 ether;
        uint256 usdtAmount = 2_000_000 * 1e6;
        address payable l1botAddr = payable(vm.addr(L1_7683_BOT_PRIVATE_KEY));

        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        logStart("Setup L1 and t1 7683 Bot liquidity");

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        // grant ETH to bot
        //        l1botAddr.transfer(ethAmount);

        // grant WETH to bot
        //        WrappedEther(L1_WETH_ADDR).transfer(l1botAddr, wethAmount);

        // grant USDT to bot
        //      T1StandardERC20(L1_USDT_ADDR).transfer(l1botAddr, usdtAmount); // 2M USDT

        vm.stopBroadcast();
        vm.startBroadcast(L1_7683_BOT_PRIVATE_KEY);

        // bridge half of bot's ETH to L2
        //    IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).depositETH{ value: ethAmount / 2 }(ethAmount / 2,
        // gasLimit);

        // bridge half of bot's WETH to L2
        //  WrappedEther(L1_WETH_ADDR).approve(L1_GATEWAY_ROUTER_PROXY_ADDR, wethAmount / 2);
        //  IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).depositERC20(L1_WETH_ADDR, wethAmount / 2, gasLimit);

        // bridge half of bot's USDT to L2
        //T1StandardERC20(L1_USDT_ADDR).approve(L1_GATEWAY_ROUTER_PROXY_ADDR, usdtAmount / 2);
        //IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).depositERC20(L1_USDT_ADDR, usdtAmount / 2, gasLimit);

        // approve L1 7683 Escrow to transfer USDT in the bot's name
        T1StandardERC20(L1_USDT_ADDR).approve(L1_T1_PULL_BASED_7683_PROXY_ADDR, usdtAmount / 2);

        // approve L1 7683 Escrow to transfer WETH in the bot's name
        WrappedEther(L1_WETH_ADDR).approve(L1_T1_PULL_BASED_7683_PROXY_ADDR, wethAmount / 2);

        vm.stopBroadcast();
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        vm.startBroadcast(L2_7683_BOT_PRIVATE_KEY);

        // approve L2 7683 Escrow to transfer USDT in the bot's name
        T1StandardERC20(L2_USDT_ADDR).approve(L2_T1_PULL_BASED_7683_PROXY_ADDR, usdtAmount / 2);

        // approve L2 7683 Escrow to transfer WETH in the bot's name

        WrappedEther(L2_WETH_ADDR).approve(L2_T1_PULL_BASED_7683_PROXY_ADDR, wethAmount / 2);

        vm.stopBroadcast();

        logStart("Setup L1 and t1 7683 Bot liquidity");
    }
}
