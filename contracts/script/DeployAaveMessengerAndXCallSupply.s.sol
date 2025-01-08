// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IWETH } from "./IWETH.sol";
import { IPool } from "aave/interfaces/IPool.sol";
import { AaveMessenger } from "../src/libraries/examples/AaveMessenger.sol";
import { IL2T1Messenger } from "../src/L2/IL2T1Messenger.sol";

contract DeployAaveMessengerAndXCallSupply is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");
        uint64 arbitrumPrivateTestnetChainId = 412346;
        address postmanAddress = 0x3f1Eae7D46d88F08fc2F8ed27FCb2AB183EB2d0E;
        IL2T1Messenger l2t1Messenger = IL2T1Messenger(0x086f77C5686dfe3F2f8FE487C5f8d357952C8556);
        IWETH weth = IWETH(0x47b8399a8A3aD9665e4257904F99eAFE043c4F50);
        IPool pool = IPool(0x6c5661ea1eEFd77E72fD770cfF402cb4E55e5de2);

        vm.startBroadcast(deployerPrivateKey);

        AaveMessenger messenger = new AaveMessenger(l2t1Messenger);

        messenger.supplyOnAave{value: 0.01 ether}(
            address(pool),
            address(weth),
            depositAmount,
            postmanAddress,
            0, // referral code
            500_000, // gas limit - this is a guess, needs research
            arbitrumPrivateTestnetChainId
        );

        vm.stopBroadcast();
    }
}