// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { WrappedEther } from "../src/L2/predeploys/WrappedEther.sol";
import {Usdt} from "../src/libraries/token/Usdt.sol";

contract DeployL1Usdt is Script {
    function run() external {
        uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);
        Usdt usdt = new Usdt(1_000_000 * 10 ** 18);
        vm.stopBroadcast();

        logAddress("L1_USDT_ADDR", address(usdt));
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
