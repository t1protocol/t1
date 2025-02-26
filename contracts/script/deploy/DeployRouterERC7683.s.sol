// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { t1_7683 } from "../../src/7683/t1_7683.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract RouterDeployScript is Script {
    uint32 constant ORIGIN_CHAIN = uint32(T1Constants.L1_CHAIN_ID); // Sepolia
    uint32 constant DESTINATION_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID); // t1 devnet
    ProxyAdmin private proxyAdmin;

    function deployL1Router() external {
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address l1Messenger = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        // Deploy L1 router implementation
        t1_7683 implementation = new t1_7683(
            l1Messenger,
            address(0), // No Permit2 for now
            ORIGIN_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSelector(t1_7683.initialize.selector, address(0), address(0), msg.sender)
        );

        console2.log("t1_7683_ADDRESS=", address(proxy));

        vm.stopBroadcast();
    }

    function deployL2Router() external {
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address l2Messenger = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        address t1_7683_PROXY_ADDR = vm.envAddress("t1_7683_PROXY_ADDR");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 router implementation
        t1_7683 implementation = new t1_7683(
            l2Messenger,
            address(0), // No Permit2 for now
            DESTINATION_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSelector(t1_7683.initialize.selector, t1_7683_PROXY_ADDR)
        );

        console2.log("t1_7683_IMPLEMENTATION_ADDR=", address(implementation));
        console2.log("t1_7683_PROXY_ADDR=", address(proxy));

        vm.stopBroadcast();
    }
}
