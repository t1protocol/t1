// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { T1XChainRead } from "../../src/libraries/x-chain/T1XChainRead.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract DeployXChainRead is Script, DeploymentUtils {
    uint32 internal constant ORIGIN_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID);
    uint32 internal constant PR1 = uint32(T1Constants.L1_CHAIN_ID);

    function deploy_to_t1() external {
        logStart("DeployXChainRead to t1");

        uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address L2_T1_MESSENGER = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        address L2_T1_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");
        ProxyAdmin proxyAdmin = ProxyAdmin(L2_T1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        T1XChainRead impl = new T1XChainRead(address(L2_T1_MESSENGER), ORIGIN_CHAIN);
        logAddress("L2_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            new bytes(0)
        );
        logAddress("L2_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        T1XChainRead(payable(proxy)).initialize(L2_T1_MESSENGER);

        vm.stopBroadcast();

        logEnd("DeployXChainRead to t1");
    }

    function deploy_to_pr1() external {
        logStart("DeployXChainRead to PR1");

        uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address L1_T1_MESSENGER = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        ProxyAdmin proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        T1XChainRead impl = new T1XChainRead(address(L1_T1_MESSENGER), PR1);
        logAddress("L1_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            new bytes(0)
        );
        logAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        T1XChainRead(payable(proxy)).initialize(L1_T1_MESSENGER);

        vm.stopBroadcast();

        logEnd("DeployXChainRead to PR1");
    }
}
