// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { T1Chain } from "../../src/L1/rollup/T1Chain.sol";
import { T1Owner } from "../../src/misc/T1Owner.sol";

/**
 * @title UpgradeT1Chain
 * @dev Script to upgrade the L1 T1Chain implementation
 *
 * This script:
 * 1. Deploys a new T1Chain implementation
 * 2. Upgrades the proxy to the new implementation
 * 3. Logs the new implementation address if everything is successful
 *
 * Usage:
 * forge script ./script/upgrade/UpgradeT1Chain.s.sol:UpgradeT1Chain --rpc-url $T1_L1_RPC --broadcast
 */

// solhint-disable max-states-count
// solhint-disable var-name-mixedcase

contract UpgradeT1Chain is Script, DeploymentUtils {
    // Private keys for transactions
    uint256 private L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
    uint256 private L1_SECURITY_COUNCIL_PRIVATE_KEY = vm.envUint("L1_SECURITY_COUNCIL_PRIVATE_KEY");

    // Security council role
    bytes32 private constant SECURITY_COUNCIL_NO_DELAY_ROLE = keccak256("SECURITY_COUNCIL_NO_DELAY_ROLE");

    // Contract addresses
    address private L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
    address private L1_T1_OWNER_ADDR = vm.envAddress("L1_T1_OWNER_ADDR");
    address private L1_T1_CHAIN_PROXY_ADDR = vm.envAddress("L1_T1_CHAIN_PROXY_ADDR");
    address private L1_MESSAGE_QUEUE_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_PROXY_ADDR");
    address private L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR =
        vm.envAddress("L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR");

    // Chain configuration
    uint64 private CHAIN_ID_L2 = uint64(vm.envUint("CHAIN_ID_L2"));

    function run() external {
        logStart("UpgradeT1Chain.s.sol");

        vm.createSelectFork(vm.rpcUrl("sepolia"));

        // Deploy new T1Chain implementation
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);
        T1Chain t1ChainImplementation =
            new T1Chain(CHAIN_ID_L2, L1_MESSAGE_QUEUE_PROXY_ADDR, L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR);
        vm.stopBroadcast();

        // Upgrade the proxy to the new implementation
        vm.startBroadcast(L1_SECURITY_COUNCIL_PRIVATE_KEY);
        ProxyAdmin proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        address currentImplementation =
            proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(L1_T1_CHAIN_PROXY_ADDR));
        console.log(
            "Upgrading T1Chain implementation from",
            vm.toString(currentImplementation),
            "to new implementation",
            vm.toString(address(t1ChainImplementation))
        );

        try T1Owner(payable(L1_T1_OWNER_ADDR))
            .execute(
                L1_PROXY_ADMIN_ADDR,
                0,
                abi.encodeWithSelector(
                    proxyAdmin.upgrade.selector,
                    ITransparentUpgradeableProxy(L1_T1_CHAIN_PROXY_ADDR),
                    address(t1ChainImplementation)
                ),
                SECURITY_COUNCIL_NO_DELAY_ROLE
            ) {
            console.log("T1Chain upgrade successful");

            // Verify the upgrade was successful
            address newImplementation =
                proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(L1_T1_CHAIN_PROXY_ADDR));

            if (newImplementation == address(t1ChainImplementation)) {
                console.log("Verification successful: Implementation is now", vm.toString(newImplementation));

                // Log the new implementation address
                logAddress("L1_T1_CHAIN_IMPLEMENTATION_ADDR", address(t1ChainImplementation));
            } else {
                console.log(
                    "Verification failed: Expected",
                    vm.toString(address(t1ChainImplementation)),
                    "but got",
                    vm.toString(newImplementation)
                );
            }
        } catch Error(string memory reason) {
            console.log("T1Chain upgrade failed:", reason);
            revert(string(abi.encodePacked("T1Chain upgrade failed: ", reason)));
        } catch (bytes memory) {
            console.log("T1Chain upgrade failed with unknown error");
            revert("T1Chain upgrade failed with unknown error");
        }

        vm.stopBroadcast();

        logEnd("UpgradeT1Chain.s.sol");
    }
}
