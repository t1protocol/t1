// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { EmptyContract } from "../../src/misc/EmptyContract.sol";

// solhint-disable var-name-mixedcase

contract DeployL2BridgeProxyPlaceholder is Script, DeploymentUtils {
    uint256 private L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    ProxyAdmin private proxyAdmin;
    EmptyContract private placeholder;

    function run() external {
        logStart("DeployL2BridgeProxyPlaceholder");

        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        // upgradable
        deployProxyAdmin();
        deployPlaceHolder();
        deployL2T1Messenger();
        deployL2ETHGateway();
        deployL2WETHGateway();
        deployL2StandardERC20Gateway();

        vm.stopBroadcast();

        logEnd("DeployL2BridgeProxyPlaceholder");
    }

    function deployProxyAdmin() internal {
        proxyAdmin = new ProxyAdmin();

        logAddress("L2_PROXY_ADMIN_ADDR", address(proxyAdmin));
    }

    function deployPlaceHolder() internal {
        placeholder = new EmptyContract();

        logAddress("L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR", address(placeholder));
    }

    function deployL2T1Messenger() internal {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy{ value: 1000 ether }(
            address(placeholder), address(proxyAdmin), new bytes(0)
        );

        logAddress("L2_T1_MESSENGER_PROXY_ADDR", address(proxy));
    }

    function deployL2StandardERC20Gateway() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR", address(proxy));
    }

    function deployL2ETHGateway() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L2_ETH_GATEWAY_PROXY_ADDR", address(proxy));
    }

    function deployL2WETHGateway() internal {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("L2_WETH_GATEWAY_PROXY_ADDR", address(proxy));
    }
}
