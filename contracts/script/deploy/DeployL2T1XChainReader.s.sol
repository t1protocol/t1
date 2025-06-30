// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { T1XChainReader } from "../../src/libraries/xChain/T1XChainReader.sol";

contract DeployL2T1XChainReader is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        logStart("DeployXChainRead to t1");

        uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L2_T1_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");
        address L2_PROVER = vm.envAddress("L2_SIGNER");
        ProxyAdmin proxyAdmin = ProxyAdmin(L2_T1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        T1XChainReader impl = new T1XChainReader(L2_PROVER);
        logAddress("L2_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("L2_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        vm.stopBroadcast();

        logEnd("DeployXChainRead to t1");
    }
}
