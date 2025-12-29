// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

contract DeployBaseT1ProxyAdmin is Script, DeploymentUtils {
    ProxyAdmin private proxyAdmin;

    function run() external {
        selectMainnetOrSepoliaFork("base");

        startBroadcastWithDeployerKeyIfItExists();

        deployProxyAdmin();
        transferProxyAdminOwnershipIfNeeded();

        vm.stopBroadcast();
    }

    function deployProxyAdmin() internal {
        proxyAdmin = new ProxyAdmin();
        logAddress("BASE_T1_PROXY_ADMIN_ADDR", address(proxyAdmin));
    }

    function transferProxyAdminOwnershipIfNeeded() internal {
        address proxyAdminOwner = vm.envOr("BASE_T1_PROXY_ADMIN_OWNER_ADDR", address(0));
        if (proxyAdminOwner != address(0)) {
            Ownable(address(proxyAdmin)).transferOwnership(proxyAdminOwner);
            logAddress("BASE_T1_PROXY_ADMIN_OWNER_ADDR", proxyAdminOwner);
        }
    }
}
