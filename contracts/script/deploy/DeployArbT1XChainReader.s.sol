// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { T1XChainReader } from "../../src/libraries/xChain/T1XChainReader.sol";

contract DeployArbT1XChainReader is DeploymentUtils {
    function run() external {
        selectMainnetOrSepoliaFork("arbitrum", IS_MAINNET);
        logStart("DeployXChainRead to ARB");

        uint256 DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ARB_T1_PROXY_ADMIN_ADDR = vm.envAddress("ARB_T1_PROXY_ADMIN_ADDR");
        address PROVER = vm.envAddress("ARB_SIGNER");
        ProxyAdmin proxyAdmin = ProxyAdmin(ARB_T1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        T1XChainReader impl = new T1XChainReader(PROVER);
        logAddress("ARB_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR", address(impl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("ARB_T1_X_CHAIN_READ_PROXY_ADDR", address(proxy));

        vm.stopBroadcast();

        logEnd("DeployXChainRead to ARB");
    }
}
