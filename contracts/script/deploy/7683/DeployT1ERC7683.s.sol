// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {T1ERC7683} from "../../../src/7683/T1ERC7683.sol";
import {T1Constants} from "../../../src/libraries/constants/T1Constants.sol";

contract DeployT1ERC7683 is Script {
    uint32 private constant ORIGIN_CHAIN = uint32(T1Constants.L1_CHAIN_ID); // Sepolia
    uint32 private constant DESTINATION_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID); // t1 devnet
    ProxyAdmin private proxyAdmin;

    function deploy_l1_7683() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address l1Messenger = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        T1ERC7683 implementation = new T1ERC7683(
            l1Messenger,
            address(0), // No Permit2 for now
            ORIGIN_CHAIN
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), new bytes(0));

        console2.log("L1_T1_7683_IMPLEMENTATION_ADDR=", address(implementation));
        console2.log("L1_T1_7683_PROXY_ADDR=", address(proxy));

        vm.stopBroadcast();
    }

    function initialize_l1_7683() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_7683_PROXY_ADDR = vm.envAddress("L1_T1_7683_PROXY_ADDR");
        address L2_T1_7683_PROXY_ADDR = vm.envAddress("L2_T1_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683(L1_T1_7683_PROXY_ADDR).initialize(L2_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }

    function deploy_l2_7683() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address l2Messenger = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 router implementation
        T1ERC7683 implementation = new T1ERC7683(
            l2Messenger,
            address(0), // No Permit2 for now
            DESTINATION_CHAIN
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), new bytes(0));

        console2.log("L2_T1_7683_IMPLEMENTATION_ADDR=", address(implementation));
        console2.log("L2_T1_7683_PROXY_ADDR=", address(proxy));

        vm.stopBroadcast();
    }

    function initialize_l2_7683() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_7683_PROXY_ADDR = vm.envAddress("L1_T1_7683_PROXY_ADDR");
        address L2_T1_7683_PROXY_ADDR = vm.envAddress("L2_T1_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683(L2_T1_7683_PROXY_ADDR).initialize(L1_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
