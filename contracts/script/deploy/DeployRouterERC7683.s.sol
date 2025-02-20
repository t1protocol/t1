// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { L1_t1_7683 } from "../../src/7683/L1_t1_7683.sol";
import { L2_t1_7683 } from "../../src/7683/L2_t1_7683.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

contract RouterDeployScript is Script {
    uint32 constant ORIGIN_CHAIN = uint32(T1Constants.L1_CHAIN_ID);     // Sepolia
    uint32 constant DESTINATION_CHAIN = 3_151_908; // t1 devnet
    ProxyAdmin private proxyAdmin;

    function deployL1Router() external {
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address l1Messenger = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        // Deploy L1 router implementation
        L1_t1_7683 implementation = new L1_t1_7683(
            l1Messenger,
            address(0), // No Permit2 for now
            ORIGIN_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSelector(L1_t1_7683.initialize.selector, address(0), address(0), msg.sender)
        );

        console2.log("L1_T1_7683_ADDRESS=", address(proxy));

        vm.stopBroadcast();
    }

    function deployL2Router() external {
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
        address l2Messenger = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        address L1_T1_7683_ADDRESS = vm.envAddress("L1_T1_7683_ADDRESS");
        address L2_PROXY_ADMIN_ADDR = vm.envAddress("L2_PROXY_ADMIN_ADDR");

        vm.startBroadcast(deployerPk);

        proxyAdmin = ProxyAdmin(L2_PROXY_ADMIN_ADDR);

        // Deploy L2 router implementation
        L2_t1_7683 implementation = new L2_t1_7683(
            l2Messenger,
            address(0), // No Permit2 for now
            DESTINATION_CHAIN
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSelector(L2_t1_7683.initialize.selector, L1_T1_7683_ADDRESS)
        );

        console2.log("L2_T1_7683_ADDRESS=", address(proxy));

        vm.stopBroadcast();
    }
}
