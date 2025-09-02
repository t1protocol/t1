// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { T1ERC7683 } from "../../src/7683/T1ERC7683.sol";

contract ArbGrantT1ERC7683Roles is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        logStart("Grant pauser roles on settler on Arbitrum");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPk);
        T1ERC7683 settler = T1ERC7683(vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR"));
        address openPauser = vm.envAddress("OPEN_PAUSER_ADDR");
        address settlementPauser = vm.envAddress("EMERGENCY_PAUSER_ADDR");
        address ARB_T1_PROXY_ADMIN_ADDR = vm.envAddress("ARB_T1_PROXY_ADMIN_ADDR");

        bytes32 DEFAULT_ADMIN_ROLE = settler.DEFAULT_ADMIN_ROLE();
        bytes32 OPEN_PAUSER_ROLE = settler.OPEN_PAUSER_ROLE();
        bytes32 SETTLE_PAUSER_ROLE = settler.SETTLE_PAUSER_ROLE();

        vm.startBroadcast(deployerPk);

        settler.grantRole(OPEN_PAUSER_ROLE, openPauser);
        settler.grantRole(SETTLE_PAUSER_ROLE, settlementPauser);
        settler.grantRole(DEFAULT_ADMIN_ROLE, ARB_T1_PROXY_ADMIN_ADDR);
        // Only revoke the initial admin if the contract has been deployed by
        // an account that is not meant to be the final admin
        if (ARB_T1_PROXY_ADMIN_ADDR != deployerAddr) {
            settler.revokeRole(DEFAULT_ADMIN_ROLE, deployerAddr);
        }

        vm.stopBroadcast();

        logEnd("Granted pauser roles on Arbitrum");
    }
}

contract BaseGrantT1ERC7683Roles is DeploymentUtils {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        logStart("Grant pauser roles on settler on Base");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPk);
        T1ERC7683 settler = T1ERC7683(vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR"));
        address openPauser = vm.envAddress("OPEN_PAUSER_ADDR");
        address settlementPauser = vm.envAddress("EMERGENCY_PAUSER_ADDR");
        address BASE_T1_PROXY_ADMIN_ADDR = vm.envAddress("BASE_T1_PROXY_ADMIN_ADDR");

        bytes32 DEFAULT_ADMIN_ROLE = settler.DEFAULT_ADMIN_ROLE();
        bytes32 OPEN_PAUSER_ROLE = settler.OPEN_PAUSER_ROLE();
        bytes32 SETTLE_PAUSER_ROLE = settler.SETTLE_PAUSER_ROLE();

        vm.startBroadcast(deployerPk);

        settler.grantRole(OPEN_PAUSER_ROLE, openPauser);
        settler.grantRole(SETTLE_PAUSER_ROLE, settlementPauser);
        settler.grantRole(DEFAULT_ADMIN_ROLE, BASE_T1_PROXY_ADMIN_ADDR);
        // Only revoke the initial admin if the contract has been deployed by
        // an account that is not meant to be the final admin
        if (BASE_T1_PROXY_ADMIN_ADDR != deployerAddr) {
            settler.revokeRole(DEFAULT_ADMIN_ROLE, deployerAddr);
        }

        vm.stopBroadcast();

        logEnd("Granted pauser roles on Base");
    }
}
