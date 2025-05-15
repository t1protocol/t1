// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { T1XChainReader } from "../../src/libraries/xChain/T1XChainReader.sol";

contract DeployL1T1XChainReader is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        logStart("DeployXChainRead to L1");

        uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_MESSENGER = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        address L1_SIGNER = vm.envAddress("L1_SIGNER");
        ProxyAdmin proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        T1XChainReader impl = new T1XChainReader(address(L1_T1_MESSENGER), L1_SIGNER);
        logAddress("L1_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        vm.stopBroadcast();

        logEnd("DeployXChainRead to L1");
    }
}
