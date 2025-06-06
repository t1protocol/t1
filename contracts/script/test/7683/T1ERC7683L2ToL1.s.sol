// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "intents-framework/ERC7683/IERC7683.sol";
import { T1ERC7683 } from "../../../src/7683/T1ERC7683.sol";
import { T1Constants } from "../../../src/libraries/constants/T1Constants.sol";

uint32 constant DESTINATION_CHAIN = uint32(T1Constants.L1_CHAIN_ID);
uint32 constant HUNDRED_USDT = 100 * 1e6;

// T1ERC7683L2ToL1

// Step 1: Setup Alice's account, sign and relay intent
contract AliceSetupScript is Script {
    uint32 private ORIGIN_CHAIN = uint32(vm.envUint("CHAIN_ID_L2"));
    T1ERC7683 public l2_7683;

    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        l2_7683 = T1ERC7683(vm.envAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR"));
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        vm.startBroadcast(alicePk);

        ERC20 inputToken = ERC20(vm.envAddress("L2_USDT_ADDR"));
        ERC20 outputToken = ERC20(vm.envAddress("L1_USDT_ADDR"));
        inputToken.approve(address(l2_7683), type(uint256).max);

        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(alice),
            recipient: TypeCasts.addressToBytes32(alice),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: HUNDRED_USDT,
            amountOut: HUNDRED_USDT,
            senderNonce: uint32(
                uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % 10_000
            ), // Random number between 0 and 9999
            originDomain: ORIGIN_CHAIN,
            destinationDomain: DESTINATION_CHAIN,
            destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR")),
            fillDeadline: uint32(block.timestamp + 24 hours),
            data: new bytes(0)
        });

        bytes memory encodedOrder = OrderEncoder.encode(orderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(encodedOrder, orderData.fillDeadline, OrderEncoder.orderDataType());

        l2_7683.open(order);

        bytes32 id = OrderEncoder.id(orderData);
        console2.logString("orderId: ");
        console2.logBytes32(id);

        console2.log("encodedOrder: ");
        console2.logBytes(encodedOrder);

        vm.stopBroadcast();
    }

    function _prepareOnchainOrder(
        bytes memory orderData,
        uint32 fillDeadline,
        bytes32 orderDataType
    )
        internal
        pure
        returns (OnchainCrossChainOrder memory)
    {
        return
            OnchainCrossChainOrder({ fillDeadline: fillDeadline, orderDataType: orderDataType, orderData: orderData });
    }
}

// Step 2: Solver fills
contract SolverFillScript is Script {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        uint256 solverPk = vm.envUint("TEST_PRIVATE_KEY");
        address solver = vm.addr(solverPk);

        vm.startBroadcast(solverPk);

        T1ERC7683 l1_7683 = T1ERC7683(vm.envAddress("L1_T1_PULL_BASED_7683_PROXY_ADDR"));
        // NOTE - orderId logged from the first step goes here (remove 0x first)
        bytes32 orderId = hex"";

        bytes memory originData = hex"";

        // Approve output tokens
        ERC20(vm.envAddress("L1_USDT_ADDR")).approve(
            address(l1_7683),
            HUNDRED_USDT // match amount from order
        );

        // Fill the order
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(solver));
        l1_7683.fill(orderId, originData, fillerData);

        vm.stopBroadcast();
    }
}

// Step 3: Settlement and Relay
contract SettlementScript is Script {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("t1"));
        uint256 settlerPk = vm.envUint("ALICE_PRIVATE_KEY");

        vm.startBroadcast(settlerPk);

        T1ERC7683 l2_7683 = T1ERC7683(vm.envAddress("L2_T1_PULL_BASED_7683_PROXY_ADDR"));

        // NOTE - orderId logged from the first step goes here (remove 0x first)
        bytes32 orderId = hex"";

        l2_7683.verifySettlement(DESTINATION_CHAIN, 1_000_000, orderId);

        vm.stopBroadcast();
    }
}
