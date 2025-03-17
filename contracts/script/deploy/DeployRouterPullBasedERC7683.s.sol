// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { t1_7683_PullBased } from "../../src/7683/t1_7683_pull_based.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract DeployRouterPullBasedERC7683 is Script {
    uint32 internal constant ORIGIN_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID);
    uint32 internal constant PR1 = 1337;
    ProxyAdmin private proxyAdmin;

    function deploy_to_pr1() external {
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(deployerPk);

        // Deploy L1 router implementation
        t1_7683_PullBased implementation = new t1_7683_PullBased(
            L1_T1_MESSENGER_PROXY_ADDR,
            address(0), // No Permit2 for now
            L1_T1_X_CHAIN_READ_PROXY_ADDR,
            PR1
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), new bytes(0));

        console2.log("L1_t1_7683_IMPLEMENTATION_ADDR=", address(implementation));
        console2.log("L1_t1_7683_PROXY_ADDR=", address(proxy));

        vm.stopBroadcast();
    }

    function initialize_pr1() external {
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_t1_7683_PROXY_ADDR = vm.envAddress("L1_t1_7683_PROXY_ADDR");
        address L2_t1_7683_PROXY_ADDR = vm.envAddress("L2_t1_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        t1_7683_PullBased(L1_t1_7683_PROXY_ADDR).initialize(L2_t1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }

    function deploy_to_t1() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L2_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        address L2_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L2_T1_X_CHAIN_READ_PROXY_ADDR");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 router implementation
        t1_7683_PullBased implementation = new t1_7683_PullBased(
            L2_T1_MESSENGER_PROXY_ADDR,
            address(0), // No Permit2 for now
            L2_T1_X_CHAIN_READ_PROXY_ADDR,
            ORIGIN_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), new bytes(0));

        console2.log("L2_t1_7683_IMPLEMENTATION_ADDR=", address(implementation));
        console2.log("L2_t1_7683_PROXY_ADDR=", address(proxy));

        vm.stopBroadcast();
    }

    function initialize_t1() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L1_t1_7683_PROXY_ADDR = vm.envAddress("L1_t1_7683_PROXY_ADDR");
        address L2_t1_7683_PROXY_ADDR = vm.envAddress("L2_t1_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        t1_7683_PullBased(L2_t1_7683_PROXY_ADDR).initialize(L1_t1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
