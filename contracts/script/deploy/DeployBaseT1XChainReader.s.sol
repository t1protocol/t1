// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { T1XChainReader } from "../../src/libraries/xChain/T1XChainReader.sol";

contract DeployBaseT1XChainReader is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        logStart("DeployXChainRead to BASE");

        uint256 DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address BASE_T1_PROXY_ADMIN_ADDR = vm.envAddress("BASE_T1_PROXY_ADMIN_ADDR");
        address PROVER = vm.envAddress("BASE_SIGNER");
        ProxyAdmin proxyAdmin = ProxyAdmin(BASE_T1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        T1XChainReader impl = new T1XChainReader(PROVER);
        logAddress("BASE_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("BASE_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        vm.stopBroadcast();

        logEnd("DeployXChainRead to BASE");
    }
}
