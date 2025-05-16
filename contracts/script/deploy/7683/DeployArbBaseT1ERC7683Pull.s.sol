// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";

import { T1ERC7683Pull } from "../../../src/7683/T1ERC7683Pull.sol";
import { T1Constants } from "../../../src/libraries/constants/T1Constants.sol";

contract DeployArbBaseT1ERC7683Pull is DeploymentUtils {
    uint32 internal constant ARB = uint32(T1Constants.ARBITRUM_SEPOLIA_CHAIN_ID);
    uint32 internal constant BASE = uint32(T1Constants.BASE_SEPOLIA_CHAIN_ID);
    ProxyAdmin private proxyAdmin;

    function arb_deploy() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        logStart("DeployT1ERC7683Pull to Arbitrum");
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ARB_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("ARB_T1_X_CHAIN_READ_PROXY_ADDR");
        address ARB_PROXY_ADMIN_ADDR = vm.envAddress("ARB_PROXY_ADMIN_ADDR");
        proxyAdmin = ProxyAdmin(ARB_PROXY_ADMIN_ADDR);

        vm.startBroadcast(deployerPk);

        // Deploy 7683 implementation
        T1ERC7683Pull impl = new T1ERC7683Pull(
            address(0), // No Permit2 for now
            ARB_T1_X_CHAIN_READ_PROXY_ADDR,
            ARB
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();

        logAddress("ARB_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));

        logEnd("DeployT1ERC7683Pull to Arbitrum");
    }

    function arb_init() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ARB_T1_7683_PROXY_ADDR = vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR");
        address BASE_T1_7683_PROXY_ADDR = vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683Pull(ARB_T1_7683_PROXY_ADDR).initialize(BASE_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }

    function base_deploy() external {
        logStart("DeployT1ERC7683Pull to Base");
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address BASE_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("BASE_T1_X_CHAIN_READ_PROXY_ADDR");
        address BASE_PROXY_ADMIN_ADDR = vm.envAddress("BASE_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(BASE_PROXY_ADMIN_ADDR);

        // Deploy 7683 implementation
        T1ERC7683Pull impl = new T1ERC7683Pull(
            address(0), // No Permit2 for now
            BASE_T1_X_CHAIN_READ_PROXY_ADDR,
            BASE
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();
        logAddress("BASE_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));
        logEnd("DeployT1ERC7683Pull to Base");
    }

    function base_init() external {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ARB_T1_7683_PROXY_ADDR = vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR");
        address BASE_T1_7683_PROXY_ADDR = vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683Pull(BASE_T1_7683_PROXY_ADDR).initialize(ARB_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
