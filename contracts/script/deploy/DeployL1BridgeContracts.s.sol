// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { L1ETHGateway } from "../../src/L1/gateways/L1ETHGateway.sol";
import { L1GatewayRouter } from "../../src/L1/gateways/L1GatewayRouter.sol";
import { L1MessageQueueWithGasPriceOracle } from "../../src/L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import { L1T1Messenger } from "../../src/L1/L1T1Messenger.sol";
import { L1StandardERC20Gateway } from "../../src/L1/gateways/L1StandardERC20Gateway.sol";
import { L1WETHGateway } from "../../src/L1/gateways/L1WETHGateway.sol";
import { L2GasPriceOracle } from "../../src/L1/rollup/L2GasPriceOracle.sol";
import { MultipleVersionRollupVerifier } from "../../src/L1/rollup/MultipleVersionRollupVerifier.sol";
import { T1Chain } from "../../src/L1/rollup/T1Chain.sol";
import { Whitelist } from "../../src/L2/predeploys/Whitelist.sol";
import { ZkEvmVerifierV1 } from "../../src/libraries/verifier/ZkEvmVerifierV1.sol";

// solhint-disable max-states-count
// solhint-disable var-name-mixedcase

contract DeployL1BridgeContracts is Script {
    uint256 private L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    uint64 private CHAIN_ID_L2 = uint64(vm.envUint("CHAIN_ID_L2"));

    address private L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");
    address private L2_WETH_ADDR = vm.envAddress("L2_WETH_ADDR");

    address private L1_PLONK_VERIFIER_ADDR = vm.envAddress("L1_PLONK_VERIFIER_ADDR");

    address private L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");

    address private L1_T1_CHAIN_PROXY_ADDR = vm.envAddress("L1_T1_CHAIN_PROXY_ADDR");
    address private L1_MESSAGE_QUEUE_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_PROXY_ADDR");
    address private L1_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");

    address private L2_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
    address private L2_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L2_ETH_GATEWAY_PROXY_ADDR");
    address private L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address private L2_WETH_GATEWAY_PROXY_ADDR = vm.envAddress("L2_WETH_GATEWAY_PROXY_ADDR");
    address private L2_T1_STANDARD_ERC20_ADDR = vm.envAddress("L2_T1_STANDARD_ERC20_ADDR");
    address private L2_T1_STANDARD_ERC20_FACTORY_ADDR = vm.envAddress("L2_T1_STANDARD_ERC20_FACTORY_ADDR");

    ZkEvmVerifierV1 private zkEvmVerifierV1;
    MultipleVersionRollupVerifier private rollupVerifier;
    ProxyAdmin private proxyAdmin;
    L1GatewayRouter private router;

    function run() external {
        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        deployZkEvmVerifierV1();
        deployMultipleVersionRollupVerifier();
        deployL1Whitelist();
        deployL1MessageQueue();
        deployL2GasPriceOracle();
        deployT1Chain();
        deployL1T1Messenger();
        deployL1GatewayRouter();
        deployL1ETHGateway();
        deployL1WETHGateway();
        deployL1StandardERC20Gateway();

        vm.stopBroadcast();
    }

    function deployZkEvmVerifierV1() internal {
        zkEvmVerifierV1 = new ZkEvmVerifierV1(L1_PLONK_VERIFIER_ADDR);

        logAddress("L1_ZKEVM_VERIFIER_V1_ADDR", address(zkEvmVerifierV1));
    }

    function deployMultipleVersionRollupVerifier() internal {
        uint256[] memory _versions = new uint256[](1);
        address[] memory _verifiers = new address[](1);
        _versions[0] = 0;
        _verifiers[0] = address(zkEvmVerifierV1);
        rollupVerifier = new MultipleVersionRollupVerifier(_versions, _verifiers);

        logAddress("L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR", address(rollupVerifier));
    }

    function deployL1Whitelist() internal {
        address owner = vm.addr(L1_DEPLOYER_PRIVATE_KEY);
        Whitelist whitelist = new Whitelist(owner);

        logAddress("L1_WHITELIST_ADDR", address(whitelist));
    }

    function deployT1Chain() internal {
        T1Chain impl = new T1Chain(CHAIN_ID_L2, L1_MESSAGE_QUEUE_PROXY_ADDR, address(rollupVerifier));

        logAddress("L1_T1_CHAIN_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL1MessageQueue() internal {
        L1MessageQueueWithGasPriceOracle impl =
            new L1MessageQueueWithGasPriceOracle(L1_T1_MESSENGER_PROXY_ADDR, L1_T1_CHAIN_PROXY_ADDR);
        logAddress("L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL1T1Messenger() internal {
        L1T1Messenger impl =
            new L1T1Messenger(L2_T1_MESSENGER_PROXY_ADDR, L1_T1_CHAIN_PROXY_ADDR, L1_MESSAGE_QUEUE_PROXY_ADDR);

        logAddress("L1_T1_MESSENGER_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL2GasPriceOracle() internal {
        L2GasPriceOracle impl = new L2GasPriceOracle();
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));
        logAddress("L2_GAS_PRICE_ORACLE_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L2_GAS_PRICE_ORACLE_PROXY_ADDR", address(proxy));
    }

    function deployL1GatewayRouter() internal {
        L1GatewayRouter impl = new L1GatewayRouter();
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), new bytes(0));

        logAddress("L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L1_GATEWAY_ROUTER_PROXY_ADDR", address(proxy));

        router = L1GatewayRouter(address(proxy));
    }

    function deployL1StandardERC20Gateway() internal {
        L1StandardERC20Gateway impl = new L1StandardERC20Gateway(
            L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR,
            address(router),
            L1_T1_MESSENGER_PROXY_ADDR,
            L2_T1_STANDARD_ERC20_ADDR,
            L2_T1_STANDARD_ERC20_FACTORY_ADDR
        );

        logAddress("L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL1ETHGateway() internal {
        L1ETHGateway impl = new L1ETHGateway(L2_ETH_GATEWAY_PROXY_ADDR, address(router), L1_T1_MESSENGER_PROXY_ADDR);

        logAddress("L1_ETH_GATEWAY_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL1WETHGateway() internal {
        L1WETHGateway impl = new L1WETHGateway(
            L1_WETH_ADDR, L2_WETH_ADDR, L2_WETH_GATEWAY_PROXY_ADDR, address(router), L1_T1_MESSENGER_PROXY_ADDR
        );

        logAddress("L1_WETH_GATEWAY_IMPLEMENTATION_ADDR", address(impl));
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
