// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { T1XChainReader } from "../../src/libraries/xChain/T1XChainReader.sol";

contract DeployPR1T1XChainReader is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        logStart("DeployXChainRead to Base Sepolia (PR1)");

        uint256 BASE_DEPLOYER_PRIVATE_KEY = vm.envUint("BASE_DEPLOYER_PRIVATE_KEY");
        address PR1_T1_MESSENGER = vm.envAddress("PR1_T1_MESSENGER_PROXY_ADDR");
        address PR1_T1_PROXY_ADMIN_ADDR = vm.envAddress("PR1_PROXY_ADMIN_ADDR");
        address PR1_SIGNER = vm.envAddress("PR1_SIGNER");
        ProxyAdmin proxyAdmin = ProxyAdmin(PR1_T1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(BASE_DEPLOYER_PRIVATE_KEY);

        T1XChainReader impl = new T1XChainReader(address(PR1_T1_MESSENGER), PR1_SIGNER);
        logAddress("PR1_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("PR1_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        vm.stopBroadcast();

        logEnd("DeployXChainRead to Base Sepolia (PR1)");
    }
}
