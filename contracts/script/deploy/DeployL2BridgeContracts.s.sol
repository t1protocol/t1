// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { L2ETHGateway } from "../../src/L2/gateways/L2ETHGateway.sol";
import { L2GatewayRouter } from "../../src/L2/gateways/L2GatewayRouter.sol";
import { L2T1Messenger } from "../../src/L2/L2T1Messenger.sol";
import { L2StandardERC20Gateway } from "../../src/L2/gateways/L2StandardERC20Gateway.sol";
import { L2WETHGateway } from "../../src/L2/gateways/L2WETHGateway.sol";
import { L1GasPriceOracle } from "../../src/L2/predeploys/L1GasPriceOracle.sol";
import { L2MessageQueue } from "../../src/L2/predeploys/L2MessageQueue.sol";
import { Whitelist } from "../../src/L2/predeploys/Whitelist.sol";
import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { T1StandardERC20Factory } from "../../src/libraries/token/T1StandardERC20Factory.sol";

// solhint-disable max-states-count
// solhint-disable var-name-mixedcase

contract DeployL2BridgeContracts is Script, DeploymentUtils {
    uint256 private L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    address private L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

    address private L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");
    address private L2_WETH_ADDR = vm.envAddress("L2_WETH_ADDR");

    L1GasPriceOracle private oracle;
    L2MessageQueue private queue;
    ProxyAdmin private proxyAdmin;
    L2GatewayRouter private router;
    T1StandardERC20Factory private factory;

    address private L2_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");

    address private L1_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
    address private L1_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ETH_GATEWAY_PROXY_ADDR");
    address private L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address private L1_WETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_WETH_GATEWAY_PROXY_ADDR");

    // predeploy contracts
    address private L1_GAS_PRICE_ORACLE_PREDEPLOY_ADDR = vm.envOr("L1_GAS_PRICE_ORACLE_PREDEPLOY_ADDR", address(0));
    address private L2_MESSAGE_QUEUE_PREDEPLOY_ADDR = vm.envOr("L2_MESSAGE_QUEUE_PREDEPLOY_ADDR", address(0));
    address private L2_WHITELIST_PREDEPLOY_ADDR = vm.envOr("L2_WHITELIST_PREDEPLOY_ADDR", address(0));

    function run() external {
        logStart("DeployL2BridgeContracts");

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);

        // predeploys
        deployL1GasPriceOracle();
        deployL2MessageQueue();
        deployL2Whitelist();

        // upgradable
        deployL2T1Messenger();
        deployL2GatewayRouter();
        deployT1StandardERC20Factory();
        deployL2StandardERC20Gateway();
        deployL2ETHGateway();
        deployL2WETHGateway();

        vm.stopBroadcast();

        logEnd("DeployL2BridgeContracts");
    }

    function deployL1GasPriceOracle() internal {
        if (L1_GAS_PRICE_ORACLE_PREDEPLOY_ADDR != address(0)) {
            oracle = L1GasPriceOracle(L1_GAS_PRICE_ORACLE_PREDEPLOY_ADDR);
            logAddress("L1_GAS_PRICE_ORACLE_ADDR", address(L1_GAS_PRICE_ORACLE_PREDEPLOY_ADDR));
            return;
        }

        address owner = vm.addr(L2_DEPLOYER_PRIVATE_KEY);
        oracle = new L1GasPriceOracle(owner);

        logAddress("L1_GAS_PRICE_ORACLE_ADDR", address(oracle));
    }

    function deployL2MessageQueue() internal {
        if (L2_MESSAGE_QUEUE_PREDEPLOY_ADDR != address(0)) {
            queue = L2MessageQueue(L2_MESSAGE_QUEUE_PREDEPLOY_ADDR);
            logAddress("L2_MESSAGE_QUEUE_ADDR", address(L2_MESSAGE_QUEUE_PREDEPLOY_ADDR));
            return;
        }

        address owner = vm.addr(L2_DEPLOYER_PRIVATE_KEY);
        queue = new L2MessageQueue(owner);

        logAddress("L2_MESSAGE_QUEUE_ADDR", address(queue));
    }

    function deployL2Whitelist() internal {
        if (L2_WHITELIST_PREDEPLOY_ADDR != address(0)) {
            logAddress("L2_WHITELIST_ADDR", address(L2_WHITELIST_PREDEPLOY_ADDR));
            return;
        }

        address owner = vm.addr(L2_DEPLOYER_PRIVATE_KEY);
        Whitelist whitelist = new Whitelist(owner);

        logAddress("L2_WHITELIST_ADDR", address(whitelist));
    }

    function deployL2T1Messenger() internal {
        L2T1Messenger impl = new L2T1Messenger(L1_T1_MESSENGER_PROXY_ADDR, address(queue));

        logAddress("L2_T1_MESSENGER_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL2GatewayRouter() internal {
        L2GatewayRouter impl = new L2GatewayRouter();
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        logAddress("L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L2_GATEWAY_ROUTER_PROXY_ADDR", address(proxy));

        router = L2GatewayRouter(address(proxy));
    }

    function deployT1StandardERC20Factory() internal {
        T1StandardERC20 tokenImpl = new T1StandardERC20();
        factory = new T1StandardERC20Factory(address(tokenImpl));

        logAddress("L2_T1_STANDARD_ERC20_ADDR", address(tokenImpl));
        logAddress("L2_T1_STANDARD_ERC20_FACTORY_ADDR", address(factory));
    }

    function deployL2StandardERC20Gateway() internal {
        L2StandardERC20Gateway impl = new L2StandardERC20Gateway(
            L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR, address(router), L2_T1_MESSENGER_PROXY_ADDR, address(factory)
        );

        logAddress("L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL2ETHGateway() internal {
        L2ETHGateway impl = new L2ETHGateway(L1_ETH_GATEWAY_PROXY_ADDR, address(router), L2_T1_MESSENGER_PROXY_ADDR);

        logAddress("L2_ETH_GATEWAY_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL2WETHGateway() internal {
        L2WETHGateway impl = new L2WETHGateway(
            L2_WETH_ADDR, L1_WETH_ADDR, L1_WETH_GATEWAY_PROXY_ADDR, address(router), L2_T1_MESSENGER_PROXY_ADDR
        );

        logAddress("L2_WETH_GATEWAY_IMPLEMENTATION_ADDR", address(impl));
    }
}
