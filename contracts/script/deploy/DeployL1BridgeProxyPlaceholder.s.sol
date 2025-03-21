// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { EmptyContract } from "../../src/misc/EmptyContract.sol";

// solhint-disable var-name-mixedcase

contract DeployL1BridgeProxyPlaceholder is Script, DeploymentUtils {
    uint256 private L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    ProxyAdmin private proxyAdmin;
    EmptyContract private placeholder;

    function run() external {
        logStart("DeployL1BridgeProxyPlaceholder.s.sol");

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        deployProxyAdmin();
        deployPlaceHolder();
        deployL1MessageQueue();
        deployT1Chain();
        deployL1ETHGateway();
        deployL1WETHGateway();
        deployL1StandardERC20Gateway();
        deployL1T1Messenger();

        vm.stopBroadcast();

        logEnd("DeployL1BridgeProxyPlaceholder.s.sol");
    }

    function deployProxyAdmin() internal {
        proxyAdmin = new ProxyAdmin();

        logAddress("L1_PROXY_ADMIN_ADDR", address(proxyAdmin));
    }

    function deployPlaceHolder() internal {
        placeholder = new EmptyContract();

        logAddress("L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR", address(placeholder));
    }

    function deployT1Chain() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L1_T1_CHAIN_PROXY_ADDR", address(proxy));
    }

    function deployL1MessageQueue() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));
        logAddress("L1_MESSAGE_QUEUE_PROXY_ADDR", address(proxy));
    }

    function deployL1StandardERC20Gateway() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR", address(proxy));
    }

    function deployL1ETHGateway() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L1_ETH_GATEWAY_PROXY_ADDR", address(proxy));
    }

    function deployL1WETHGateway() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L1_WETH_GATEWAY_PROXY_ADDR", address(proxy));
    }

    function deployL1T1Messenger() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy{ value: 1 ether }(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L1_T1_MESSENGER_PROXY_ADDR", address(proxy));
    }
}
