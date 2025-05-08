// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../../lib/DeploymentUtils.sol";

import { T1ERC7683Pull } from "../../../src/7683/T1ERC7683Pull.sol";
import { T1Constants } from "../../../src/libraries/constants/T1Constants.sol";

contract DeployT1ERC7683Pull is DeploymentUtils {
    uint32 internal constant T1 = uint32(T1Constants.T1_DEVNET_CHAIN_ID);
    uint32 internal constant L1 = uint32(T1Constants.L1_CHAIN_ID);
    uint32 internal constant PR1 = uint32(T1Constants.PR1_CHAIN_ID);
    ProxyAdmin private proxyAdmin;

    function l1_deploy() external {
        logStart("DeployT1ERC7683Pull to L1");
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(deployerPk);

        // Deploy L1 7683 implementation
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

        logEnd("DeployT1ERC7683Pull to L1");
    }

    function l1_init() external {
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_7683_PROXY_ADDR = vm.envAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR");
        address L2_T1_7683_PROXY_ADDR = vm.envAddress("L1_L2_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683Pull(L1_T1_7683_PROXY_ADDR).initialize(L2_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }

    function t1_deploy(string calldata bridgePrefix) external {
        logStart("DeployT1ERC7683Pull to t1");
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L2_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("L2_T1_X_CHAIN_READ_PROXY_ADDR");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 7683 implementation
        T1ERC7683Pull impl = new T1ERC7683Pull(
            address(0), // No Permit2 for now
            L2_T1_X_CHAIN_READ_PROXY_ADDR,
            T1
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();

        logAddress(string(abi.encodePacked(bridgePrefix, "_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR")), address(impl));
        logAddress(string(abi.encodePacked(bridgePrefix, "_T1_PULL_BASED_7683_PROXY_ADDR")), address(proxy));

        logEnd("DeployT1ERC7683Pull to t1");
    }

    function t1_init(string calldata counterpartPrefix, string calldata bridgePrefix) external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address counterpart =
            vm.envAddress(string(abi.encodePacked(counterpartPrefix, "_T1_PULL_BASED_7683_PROXY_ADDR")));
        address L2_T1_7683_PROXY_ADDR =
            vm.envAddress(string(abi.encodePacked(bridgePrefix, "_T1_PULL_BASED_7683_PROXY_ADDR")));

        vm.startBroadcast(deployerPk);

        T1ERC7683Pull(L2_T1_7683_PROXY_ADDR).initialize(counterpart);

        vm.stopBroadcast();
    }

    function pr1_deploy() external {
        logStart("DeployT1ERC7683Pull to PR1");
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        uint256 deployerPk = vm.envUint("PR1_DEPLOYER_PRIVATE_KEY");
        address PR1_T1_X_CHAIN_READ_PROXY_ADDR = vm.envAddress("PR1_T1_X_CHAIN_READ_PROXY_ADDR");
        address PR1_PROXY_ADMIN_ADDR = vm.envAddress("PR1_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(PR1_PROXY_ADMIN_ADDR);

        // Deploy PR1 7683 implementation
        T1ERC7683Pull impl = new T1ERC7683Pull(
            address(0), // No Permit2 for now
            PR1_T1_X_CHAIN_READ_PROXY_ADDR,
            PR1
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        vm.stopBroadcast();

        logAddress("PR1_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(impl));
        logAddress("PR1_T1_PULL_BASED_7683_PROXY_ADDR", address(proxy));

        logEnd("DeployT1ERC7683Pull to PR1");
    }

    function pr1_init() external {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        uint256 deployerPk = vm.envUint("PR1_DEPLOYER_PRIVATE_KEY");
        address PR1_T1_7683_PROXY_ADDR = vm.envAddress("PR1_T1_PULL_BASED_7683_PROXY_ADDR");
        address L2_T1_7683_PROXY_ADDR = vm.envAddress("PR1_L2_T1_PULL_BASED_7683_PROXY_ADDR");

        vm.startBroadcast(deployerPk);

        T1ERC7683Pull(PR1_T1_7683_PROXY_ADDR).initialize(L2_T1_7683_PROXY_ADDR);

        vm.stopBroadcast();
    }
}
