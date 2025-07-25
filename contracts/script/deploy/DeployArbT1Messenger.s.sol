// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";
import { EmptyContract } from "../../src/misc/EmptyContract.sol";
import { L2T1Messenger } from "../../src/L2/L2T1Messenger.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";
import { L2MessageQueue } from "../../src/L2/predeploys/L2MessageQueue.sol";
import { T1Owner } from "../../src/misc/T1Owner.sol";

import { Script } from "forge-std/Script.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployArbT1MessengerProxy is Script, DeploymentUtils {
    uint256 private deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    ProxyAdmin private proxyAdmin;
    EmptyContract private placeholder;
    TransparentUpgradeableProxy private proxy;

    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        vm.startBroadcast(deployerPrivateKey);
        deployPlaceHolder();
        deployT1MessengerProxy();
    }

    function deployPlaceHolder() internal {
        placeholder = new EmptyContract();

        logAddress("ARB_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR", address(placeholder));
    }

    function deployT1MessengerProxy() internal {
        proxy = new TransparentUpgradeableProxy(address(placeholder), address(proxyAdmin), new bytes(0));

        logAddress("ARB_T1_MESSENGER_PROXY_ADDR", address(proxy));
    }
}

contract DeployArbT1MessengerImplAndInit is Script, DeploymentUtils {
    uint256 private deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address private ARB_T1_PROXY_ADMIN_ADDR = vm.envAddress("ARB_T1_PROXY_ADMIN_ADDR");
    address private ARB_T1_MESSENGER_PROXY_ADDR = vm.envAddress("ARB_T1_MESSENGER_PROXY_ADDR");
    address private BASE_T1_MESSENGER_PROXY_ADDR = vm.envAddress("BASE_T1_MESSENGER_PROXY_ADDR");

    ProxyAdmin private proxyAdmin;
    L2MessageQueue private queue;
    L2T1Messenger private impl;
    TransparentUpgradeableProxy private proxy;

    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        vm.startBroadcast(deployerPrivateKey);
        proxyAdmin = ProxyAdmin(ARB_T1_PROXY_ADMIN_ADDR);
        proxy = TransparentUpgradeableProxy(payable(ARB_T1_MESSENGER_PROXY_ADDR));
        deployMessageQueue();
        deployT1MessengerImpl();
        upgradeAndInitializeT1MessengerProxy();
    }

    function deployMessageQueue() internal {
        address deployer = vm.addr(deployerPrivateKey);
        queue = new L2MessageQueue(deployer);

        logAddress("ARB_T1_MESSAGE_QUEUE_ADDR", address(queue));
    }

    function deployT1MessengerImpl() internal {
        impl = new L2T1Messenger(BASE_T1_MESSENGER_PROXY_ADDR, address(queue));

        logAddress("ARB_T1_MESSENGER_IMPLEMENTATION_ADDR", address(impl));
    }

    function upgradeAndInitializeT1MessengerProxy() internal {
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxy)), address(impl));

        uint64[] memory network = new uint64[](1);
        network[0] = T1Constants.BASE_SEPOLIA_CHAIN_ID;
        L2T1Messenger(payable(address(proxy))).initialize(BASE_T1_MESSENGER_PROXY_ADDR, network);
    }
}

contract DeployArbT1MessengerOwnerAndTransferOwnership is Script, DeploymentUtils {
    uint256 private deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address private ARB_T1_PROXY_ADMIN_ADDR = vm.envAddress("ARB_T1_PROXY_ADMIN_ADDR");

    ProxyAdmin private proxyAdmin;
    T1Owner private owner;

    function run() external {
        vm.createSelectFork(vm.rpcUrl("arbitrum_sepolia"));
        vm.startBroadcast(deployerPrivateKey);
        proxyAdmin = ProxyAdmin(ARB_T1_PROXY_ADMIN_ADDR);
        deployT1Owner();
        transferOwnership();
    }

    function deployT1Owner() internal {
        owner = new T1Owner();
        logAddress("ARB_T1_OWNER_ADDR", address(owner));
    }

    function transferOwnership() internal {
        Ownable(proxyAdmin).transferOwnership(address(owner));
    }
}
