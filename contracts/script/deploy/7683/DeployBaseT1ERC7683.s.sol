// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";

import { T1ERC7683 } from "../../../src/7683/T1ERC7683.sol";
import { T1Constants } from "../../../src/libraries/constants/T1Constants.sol";

contract DeployBaseT1ERC7683 is DeploymentUtils {
    uint32 internal constant ARB = uint32(T1Constants.ARBITRUM_SEPOLIA_CHAIN_ID);
    uint32 internal constant BASE = uint32(T1Constants.BASE_SEPOLIA_CHAIN_ID);
    ProxyAdmin private proxyAdmin;

    function deploy() external {
        logStart("DeployT1ERC7683 to Base");
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address BASE_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("BASE_T1_X_CHAIN_READ_PROXY_ADDR");
        address BASE_T1_PROXY_ADMIN_ADDR = vm.envAddress("BASE_T1_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(BASE_T1_PROXY_ADMIN_ADDR);

        T1ERC7683 impl = new T1ERC7683(
            address(0), // No Permit2 for now
            BASE_T1_X_CHAIN_READ_PROXY_ADDR,
            BASE
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();
        logAddress("BASE_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));
        logEnd("DeployT1ERC7683 to Base");
    }

    function init() external {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ARB_T1_7683_PROXY_ADDR = vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR");
        address BASE_T1_7683_PROXY_ADDR = vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683(BASE_T1_7683_PROXY_ADDR).initialize(ARB_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
