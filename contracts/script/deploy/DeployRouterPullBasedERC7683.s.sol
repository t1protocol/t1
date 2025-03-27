// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { t1_7683_PullBased } from "../../src/7683/t1_7683_pull_based.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract DeployRouterPullBasedERC7683 is DeploymentUtils  {
    uint32 internal constant ORIGIN_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID);
    uint32 internal constant PR1 = uint32(T1Constants.L1_CHAIN_ID);
    ProxyAdmin private proxyAdmin;

    function deploy_to_pr1() external {
        logStart("DeployRouterPullBasedERC7683 to PR1");
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(deployerPk);

        // Deploy L1 router implementation
        t1_7683_PullBased impl = new t1_7683_PullBased(
            L1_T1_MESSENGER_PROXY_ADDR,
            address(0), // No Permit2 for now
            L1_T1_X_CHAIN_READ_PROXY_ADDR,
            PR1
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();

        logAddress("L1_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));

        logEnd("DeployRouterPullBasedERC7683 to PR1");
    }

    function initialize_pr1() external {
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_t1_7683_PROXY_ADDR = vm.envAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR");
        address L2_t1_7683_PROXY_ADDR = vm.envAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        t1_7683_PullBased(L1_t1_7683_PROXY_ADDR).initialize(L2_t1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }

    function deploy_to_t1() external {
        logStart("DeployRouterPullBasedERC7683 to t1");
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L2_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        address L2_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L2_T1_X_CHAIN_READ_PROXY_ADDR");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 router implementation
        t1_7683_PullBased impl = new t1_7683_PullBased(
            L2_T1_MESSENGER_PROXY_ADDR,
            address(0), // No Permit2 for now
            L2_T1_X_CHAIN_READ_PROXY_ADDR,
            ORIGIN_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();

        logAddress("L2_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));

        logEnd("DeployRouterPullBasedERC7683 to t1");
    }

    function initialize_t1() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L1_t1_7683_PROXY_ADDR = vm.envAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR");
        address L2_t1_7683_PROXY_ADDR = vm.envAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        t1_7683_PullBased(L2_t1_7683_PROXY_ADDR).initialize(L1_t1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
