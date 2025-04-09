// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { t1XChainReader } from "../../src/libraries/xChain/t1XChainReader.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract DeployPR1t1XChainReader is DeploymentUtils {
    uint32 internal constant PR1 = uint32(T1Constants.L1_CHAIN_ID);

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        logStart("DeployXChainRead to PR1");

        uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_MESSENGER = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        ProxyAdmin proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        t1XChainReader impl = new t1XChainReader(address(L1_T1_MESSENGER), PR1);
        logAddress("L1_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        vm.stopBroadcast();

        logEnd("DeployXChainRead to PR1");
    }
}
