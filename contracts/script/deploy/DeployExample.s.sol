// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { IL2T1Messenger } from "../../src/L2/IL2T1Messenger.sol";

contract Example {
    IL2T1Messenger public immutable L2_MESSENGER;

    constructor(IL2T1Messenger _l2Messenger) {
        L2_MESSENGER = _l2Messenger;
    }
}

contract DeployExample is Script {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        address l2Messenger = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPk);

        Example example = new Example(IL2T1Messenger(l2Messenger));

        console2.log("EXAMPLE_ADDR=", address(example));

        vm.stopBroadcast();
    }
}
