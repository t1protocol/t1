// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { L2T1Messenger } from "../src/L2/L2T1Messenger.sol";
import { L2ETHGateway } from "../src/L2/gateways/L2ETHGateway.sol";
import { L2GatewayRouter } from "../src/L2/gateways/L2GatewayRouter.sol";
import { L2StandardERC20Gateway } from "../src/L2/gateways/L2StandardERC20Gateway.sol";
import { L2MessageQueue } from "../src/L2/predeploys/L2MessageQueue.sol";
import { L1GasPriceOracle } from "../src/L2/predeploys/L1GasPriceOracle.sol";
import { T1StandardERC20Factory } from "../src/libraries/token/T1StandardERC20Factory.sol";
import { T1Constants } from "../src/libraries/constants/T1Constants.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract InitializeL2BridgeContracts is Script {
    uint256 deployerPrivateKey = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

    address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

    address L1_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
    address L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address L1_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ETH_GATEWAY_PROXY_ADDR");
    address L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");

    address L1_GAS_PRICE_ORACLE_ADDR = vm.envAddress("L1_GAS_PRICE_ORACLE_ADDR");
    address L2_WHITELIST_ADDR = vm.envAddress("L2_WHITELIST_ADDR");
    address L2_MESSAGE_QUEUE_ADDR = vm.envAddress("L2_MESSAGE_QUEUE_ADDR");

    address L2_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
    address L2_T1_MESSENGER_IMPLEMENTATION_ADDR = vm.envAddress("L2_T1_MESSENGER_IMPLEMENTATION_ADDR");
    address L2_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L2_GATEWAY_ROUTER_PROXY_ADDR");
    address L2_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L2_ETH_GATEWAY_PROXY_ADDR");
    address L2_ETH_GATEWAY_IMPLEMENTATION_ADDR = vm.envAddress("L2_ETH_GATEWAY_IMPLEMENTATION_ADDR");
    address L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR =
        vm.envAddress("L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR");
    address L2_T1_STANDARD_ERC20_FACTORY_ADDR = vm.envAddress("L2_T1_STANDARD_ERC20_FACTORY_ADDR");

    function run() external {
        ProxyAdmin proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        vm.startBroadcast(deployerPrivateKey);

        // note: we use call upgrade(...) and initialize(...) instead of upgradeAndCall(...),
        // otherwise the contract owner would become ProxyAdmin.

        // initialize L2MessageQueue
        L2MessageQueue(L2_MESSAGE_QUEUE_ADDR).initialize(L2_T1_MESSENGER_PROXY_ADDR);

        // initialize L1GasPriceOracle
        L1GasPriceOracle(L1_GAS_PRICE_ORACLE_ADDR).updateWhitelist(L2_WHITELIST_ADDR);

        // initialize L2T1Messenger
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L2_T1_MESSENGER_PROXY_ADDR), L2_T1_MESSENGER_IMPLEMENTATION_ADDR
        );

        uint64[] memory network = new uint64[](1);
        network[0] = T1Constants.ETH_CHAIN_ID;
        L2T1Messenger(payable(L2_T1_MESSENGER_PROXY_ADDR)).initialize(L1_T1_MESSENGER_PROXY_ADDR, network);

        // initialize L2GatewayRouter
        L2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).initialize(
            L2_ETH_GATEWAY_PROXY_ADDR, L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR
        );

        // initialize L2ETHGateway
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(L2_ETH_GATEWAY_PROXY_ADDR), L2_ETH_GATEWAY_IMPLEMENTATION_ADDR);

        L2ETHGateway(L2_ETH_GATEWAY_PROXY_ADDR).initialize();

        // initialize L2StandardERC20Gateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );

        L2StandardERC20Gateway(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR).initialize();

        // initialize T1StandardERC20Factory
        T1StandardERC20Factory(L2_T1_STANDARD_ERC20_FACTORY_ADDR).transferOwnership(
            L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR
        );

        vm.stopBroadcast();
    }
}
