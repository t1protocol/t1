// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { t1_7683 } from "../../src/7683/t1_7683.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract DeployRouterERC7683 is Script {
    uint32 constant ORIGIN_CHAIN = uint32(T1Constants.L1_CHAIN_ID); // Sepolia
    uint32 constant DESTINATION_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID); // t1 devnet
    ProxyAdmin private proxyAdmin;

    function deployL1Router() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address l1Messenger = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        // Deploy L1 router implementation
        t1_7683 implementation = new t1_7683(
            l1Messenger,
            address(0), // No Permit2 for now
            ORIGIN_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), new bytes(0));

        console2.log("L1_t1_7683_IMPLEMENTATION_ADDR=", address(implementation));
        console2.log("L1_t1_7683_PROXY_ADDR=", address(proxy));

        vm.stopBroadcast();
    }

    function initializeL1Router() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_t1_7683_PROXY_ADDR = vm.envAddress("L1_t1_7683_PROXY_ADDR");
        address L2_t1_7683_PROXY_ADDR = vm.envAddress("L2_t1_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        t1_7683(L1_t1_7683_PROXY_ADDR).initialize(L2_t1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }

    function deployL2Router() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address l2Messenger = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 router implementation
        t1_7683 implementation = new t1_7683(
            l2Messenger,
            address(0), // No Permit2 for now
            DESTINATION_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), new bytes(0));

        console2.log("L2_t1_7683_IMPLEMENTATION_ADDR=", address(implementation));
        console2.log("L2_t1_7683_PROXY_ADDR=", address(proxy));

        vm.stopBroadcast();
    }

    function initializeL2Router() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_t1_7683_PROXY_ADDR = vm.envAddress("L1_t1_7683_PROXY_ADDR");
        address L2_t1_7683_PROXY_ADDR = vm.envAddress("L2_t1_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        t1_7683(L2_t1_7683_PROXY_ADDR).initialize(L1_t1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
