// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { T1ERC7683 } from "../../src/7683/T1ERC7683.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract UpgradeArbT1ERC7683 is DeploymentUtils {
    address internal ARB_T1_PROXY_ADMIN_ADDR = vm.envAddress("ARB_T1_PROXY_ADMIN_ADDR");
    address internal AUCTION_WITNESS = vm.envAddress("AUCTION_WITNESS");
    address internal ARB_T1_X_CHAIN_READ_PROXY_ADDR = vm.envOr("ARB_T1_X_CHAIN_READ_PROXY_ADDR", address(0));
    address internal BASE_T1_7683_PROXY_ADDR = vm.envOr("BASE_T1_PULL_BASED_7683_PROXY_ADDR", address(0));
    address internal ARB_T1_7683_PROXY_ADDR = vm.envOr("ARB_T1_PULL_BASED_7683_PROXY_ADDR", address(0));
    uint32 internal immutable ARB =
        uint32(IS_MAINNET ? T1Constants.ARBITRUM_MAINNET_CHAIN_ID : T1Constants.ARBITRUM_SEPOLIA_CHAIN_ID);
    uint32 internal immutable BASE =
        uint32(IS_MAINNET ? T1Constants.BASE_MAINNET_CHAIN_ID : T1Constants.BASE_SEPOLIA_CHAIN_ID);

    ProxyAdmin private proxyAdmin;

    function upgrade() external {
        logStart("Upgrade T1ERC7683 on Arbitrum");
        selectMainnetOrSepoliaFork("arbitrum");
        startBroadcastWithDeployerKeyIfItExists();

        proxyAdmin = ProxyAdmin(ARB_T1_PROXY_ADMIN_ADDR);

        // Deploy new implementation
        T1ERC7683 newImpl = new T1ERC7683(
            address(0), // No Permit2 for now
            ARB_T1_X_CHAIN_READ_PROXY_ADDR,
            ARB
        );

        // Upgrade the existing proxy to the new implementation
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(ARB_T1_7683_PROXY_ADDR), address(newImpl));

        vm.stopBroadcast();
        logAddress("ARB_T1_PULL_BASED_7683_IMPLEMENTATION_ADDR", address(newImpl));
        logAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR", ARB_T1_7683_PROXY_ADDR);
        logEnd("Upgrade T1ERC7683 on Arbitrum");
    }
}
