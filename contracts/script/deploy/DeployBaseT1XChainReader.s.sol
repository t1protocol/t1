// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { T1XChainReader } from "../../src/libraries/xChain/T1XChainReader.sol";

contract DeployBaseT1XChainReader is DeploymentUtils {
    address internal BASE_T1_PROXY_ADMIN_ADDR = vm.envAddress("BASE_T1_PROXY_ADMIN_ADDR");
    address internal PROVER = vm.envAddress("BASE_SIGNER");
    address internal MANAGER_MULTISIG = vm.envAddress("MANAGER_MULTISIG_ADDR");

    function run() external {
        selectMainnetOrSepoliaFork("base");
        logStart("DeployXChainRead to BASE");
        ProxyAdmin proxyAdmin = ProxyAdmin(BASE_T1_PROXY_ADMIN_ADDR);

        startBroadcastWithDeployerKeyIfItExists();

        T1XChainReader impl = new T1XChainReader(PROVER);
        logAddress("BASE_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("BASE_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        T1XChainReader(address(proxy)).initialize(MANAGER_MULTISIG);

        vm.stopBroadcast();

        logEnd("DeployXChainRead to BASE");
    }
}
