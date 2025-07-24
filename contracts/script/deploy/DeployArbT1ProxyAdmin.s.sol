// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DeploymentUtils} from "../lib/DeploymentUtils.sol";

contract DeployArbT1ProxyAdmin is Script, DeploymentUtils {
    uint256 private deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    ProxyAdmin private proxyAdmin;
    TransparentUpgradeableProxy private proxy;

    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        vm.startBroadcast(deployerPrivateKey);
        deployProxyAdmin();
    }

    function deployProxyAdmin() internal {
        proxyAdmin = new ProxyAdmin();
        logAddress("ARB_T1_PROXY_ADMIN_ADDR", address(proxyAdmin));
    }
}
