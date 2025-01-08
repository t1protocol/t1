// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IWETH } from "./IWETH.sol";
import { IPool } from "aave/interfaces/IPool.sol";

contract SupplyWethToAavePool is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");
        address deployerAddress = vm.addr(deployerPrivateKey);
        IWETH weth = IWETH(0x47b8399a8A3aD9665e4257904F99eAFE043c4F50);
        IPool pool = IPool(0x6c5661ea1eEFd77E72fD770cfF402cb4E55e5de2);
        
        vm.startBroadcast(deployerPrivateKey);

        weth.deposit{value: depositAmount}();
        weth.approve(address(pool), depositAmount);
        pool.supply(address(weth), depositAmount, deployerAddress, 0);

        vm.stopBroadcast();
    }
}