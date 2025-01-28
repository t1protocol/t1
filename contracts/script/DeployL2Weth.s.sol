// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { WrappedEther } from "../src/L2/predeploys/WrappedEther.sol";

contract DeployL2Weth is Script {
    address L2_WETH_ADDR = vm.envAddress("L2_WETH_ADDR");

    function run() external {

        if (L2_WETH_ADDR == address(0)) {
            uint256 L2_DEPLOYER_PRIVATE_KEY = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");
            vm.startBroadcast(L2_DEPLOYER_PRIVATE_KEY);
            WrappedEther weth = new WrappedEther();
            L2_WETH_ADDR = address(weth);
            weth.deposit{ value: 100 ether }();
            vm.stopBroadcast();
        }

        logAddress("L2_WETH_ADDR", L2_WETH_ADDR);
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
