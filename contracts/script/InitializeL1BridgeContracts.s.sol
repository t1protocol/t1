// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { L1ETHGateway } from "../src/L1/gateways/L1ETHGateway.sol";
import { L1GatewayRouter } from "../src/L1/gateways/L1GatewayRouter.sol";
import { L1T1Messenger } from "../src/L1/L1T1Messenger.sol";
import { L1StandardERC20Gateway } from "../src/L1/gateways/L1StandardERC20Gateway.sol";
import { T1Chain } from "../src/L1/rollup/T1Chain.sol";
import { L1MessageQueueWithGasPriceOracle } from "../src/L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import { L2GasPriceOracle } from "../src/L1/rollup/L2GasPriceOracle.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract InitializeL1BridgeContracts is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    uint256 CHAIN_ID_L2 = vm.envUint("CHAIN_ID_L2");
    uint256 MAX_TX_IN_CHUNK = vm.envUint("MAX_TX_IN_CHUNK");
    uint256 MAX_L1_MESSAGE_GAS_LIMIT = vm.envUint("MAX_L1_MESSAGE_GAS_LIMIT");
    address L1_COMMIT_SENDER_ADDRESS = vm.envAddress("L1_COMMIT_SENDER_ADDRESS");
    address L1_FINALIZE_SENDER_ADDRESS = vm.envAddress("L1_FINALIZE_SENDER_ADDRESS");
    address L1_FEE_VAULT_ADDR = vm.envAddress("L1_FEE_VAULT_ADDR");

    address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");

    address L1_WHITELIST_ADDR = vm.envAddress("L1_WHITELIST_ADDR");
    address L1_T1_CHAIN_PROXY_ADDR = vm.envAddress("L1_T1_CHAIN_PROXY_ADDR");
    address L1_T1_CHAIN_IMPLEMENTATION_ADDR = vm.envAddress("L1_T1_CHAIN_IMPLEMENTATION_ADDR");
    address L1_MESSAGE_QUEUE_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_PROXY_ADDR");
    address L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR");
    address L2_GAS_PRICE_ORACLE_PROXY_ADDR = vm.envAddress("L2_GAS_PRICE_ORACLE_PROXY_ADDR");
    address L1_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
    address L1_T1_MESSENGER_IMPLEMENTATION_ADDR = vm.envAddress("L1_T1_MESSENGER_IMPLEMENTATION_ADDR");
    address L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address L1_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ETH_GATEWAY_PROXY_ADDR");
    address L1_ETH_GATEWAY_IMPLEMENTATION_ADDR = vm.envAddress("L1_ETH_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR =
        vm.envAddress("L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR = vm.envAddress("L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR");

    address L2_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
    address L2_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L2_ETH_GATEWAY_PROXY_ADDR");
    address L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address L2_T1_STANDARD_ERC20_ADDR = vm.envAddress("L2_T1_STANDARD_ERC20_ADDR");
    address L2_T1_STANDARD_ERC20_FACTORY_ADDR = vm.envAddress("L2_T1_STANDARD_ERC20_FACTORY_ADDR");

    function run() external {
        ProxyAdmin proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        // note: we use call upgrade(...) and initialize(...) instead of upgradeAndCall(...),
        // otherwise the contract owner would become ProxyAdmin.

        // initialize T1Chain
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(L1_T1_CHAIN_PROXY_ADDR), L1_T1_CHAIN_IMPLEMENTATION_ADDR);

        T1Chain(L1_T1_CHAIN_PROXY_ADDR).initialize(MAX_TX_IN_CHUNK);

        T1Chain(L1_T1_CHAIN_PROXY_ADDR).addSequencer(L1_COMMIT_SENDER_ADDRESS);
        T1Chain(L1_T1_CHAIN_PROXY_ADDR).addProver(L1_FINALIZE_SENDER_ADDRESS);

        // initialize L2GasPriceOracle
        L2GasPriceOracle(L2_GAS_PRICE_ORACLE_PROXY_ADDR).initialize(
            21_000, // _txGas
            53_000, // _txGasContractCreation
            4, // _zeroGas
            16 // _nonZeroGas
        );
        L2GasPriceOracle(L2_GAS_PRICE_ORACLE_PROXY_ADDR).updateWhitelist(L1_WHITELIST_ADDR);

        // initialize L1MessageQueueWithGasPriceOracle
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_MESSAGE_QUEUE_PROXY_ADDR), L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR
        );

        L1MessageQueueWithGasPriceOracle(L1_MESSAGE_QUEUE_PROXY_ADDR).initialize(
            L2_GAS_PRICE_ORACLE_PROXY_ADDR, MAX_L1_MESSAGE_GAS_LIMIT
        );

        L1MessageQueueWithGasPriceOracle(L1_MESSAGE_QUEUE_PROXY_ADDR).initializeV2();

        // initialize L1T1Messenger
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_T1_MESSENGER_PROXY_ADDR), L1_T1_MESSENGER_IMPLEMENTATION_ADDR
        );

        L1T1Messenger(payable(L1_T1_MESSENGER_PROXY_ADDR)).initialize(L1_FEE_VAULT_ADDR);

        // initialize L1GatewayRouter
        L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).initialize(
            L1_ETH_GATEWAY_PROXY_ADDR, L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR
        );

        // initialize L1ETHGateway
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(L1_ETH_GATEWAY_PROXY_ADDR), L1_ETH_GATEWAY_IMPLEMENTATION_ADDR);

        L1ETHGateway(L1_ETH_GATEWAY_PROXY_ADDR).initialize();

        // initialize L1StandardERC20Gateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );

        L1StandardERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).initialize();

        vm.stopBroadcast();
    }
}
