// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { L1WETHGateway } from "../../src/L1/gateways/L1WETHGateway.sol";
import { Script } from "forge-std/Script.sol";
import { WrappedEther } from "../../src/L2/predeploys/WrappedEther.sol";
import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { IL1ERC20Gateway } from "../../src/L1/gateways/IL1ERC20Gateway.sol";

import { console } from "forge-std/console.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DepositUsdtFromL1ToL2 is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    address L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR =
        vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");

    address payable L1_USDT_ADDR = payable(vm.envAddress("L1_USDT_ADDR"));

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        uint256 gasLimit = 1_000_000;

        T1StandardERC20(L1_USDT_ADDR).approve(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR, 0.01 ether);

        IL1ERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).depositERC20(L1_USDT_ADDR, 0.01 ether, gasLimit);

        address l2usdtAddress = IL1ERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).getL2ERC20Address(L1_USDT_ADDR);
        logAddress("L2_USDT_ADDR", l2usdtAddress);

        vm.stopBroadcast();
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
