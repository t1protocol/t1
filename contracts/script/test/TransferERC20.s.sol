// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TransferERC20 is Script {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        uint256 alicePk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(alicePk);

        ERC20 token = ERC20(vm.envAddress("BASE_SEPOLIA_USDT_ADDR"));
        address recipient = 0x2Ade71354645C57e7D099DbC04b27f8ad277395E;
        uint256 decimals = token.decimals();
        uint256 amount = 10_000 * 10 ** decimals;
        token.transfer(recipient, amount);

        vm.stopBroadcast();
    }
}
