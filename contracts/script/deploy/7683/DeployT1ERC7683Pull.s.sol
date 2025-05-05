// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";

import { T1ERC7683Pull } from "../../../src/7683/T1ERC7683Pull.sol";
import { T1Constants } from "../../../src/libraries/constants/T1Constants.sol";

uint32 constant T1 = uint32(T1Constants.T1_DEVNET_CHAIN_ID);
uint32 constant L1 = uint32(T1Constants.L1_CHAIN_ID);

contract DeployT1ERC7683PullL1 is DeploymentUtils {
    ProxyAdmin private proxyAdmin;

    function run() external {
        logStart("DeployRouterPullBasedERC7683 to L1");
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(deployerPk);

        // Deploy L1 router implementation
        T1ERC7683Pull impl = new T1ERC7683Pull(
            address(0), // No Permit2 for now
            L1_T1_X_CHAIN_READ_PROXY_ADDR,
            L1
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();

        logAddress("L1_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));

        logEnd("DeployRouterPullBasedERC7683 to L1");
    }
}

contract DeployT1ERC7683PullT1 is DeploymentUtils {
    ProxyAdmin private proxyAdmin;

    function run() external {
        logStart("DeployRouterPullBasedERC7683 to t1");
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L2_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L2_T1_X_CHAIN_READ_PROXY_ADDR");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 router implementation
        T1ERC7683Pull impl = new T1ERC7683Pull(
            address(0), // No Permit2 for now
            L2_T1_X_CHAIN_READ_PROXY_ADDR,
            T1
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();

        logAddress("L2_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));

        logEnd("DeployRouterPullBasedERC7683 to t1");
    }
}

contract InitT1ERC7683PullL1 is DeploymentUtils {
    function run() external {
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_7683_PROXY_ADDR = vm.envAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR");
        address L2_T1_7683_PROXY_ADDR = vm.envAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683Pull(L1_T1_7683_PROXY_ADDR).initialize(L2_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}

contract InitT1ERC7683PullT1 is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L1_T1_7683_PROXY_ADDR = vm.envAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR");
        address L2_T1_7683_PROXY_ADDR = vm.envAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683Pull(L2_T1_7683_PROXY_ADDR).initialize(L1_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
