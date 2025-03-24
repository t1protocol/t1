// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OrderData, OrderEncoder } from "intents-framework/libs/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "intents-framework/ERC7683/IERC7683.sol";
import { t1_7683 } from "../../src/7683/t1_7683.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

uint32 constant ORIGIN_CHAIN = uint32(T1Constants.L1_CHAIN_ID);
uint32 constant DESTINATION_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID);

// Step 1: Setup Alice's account, sign and relay intent
contract AliceSetupScript is Script {
    t1_7683 public l1Router;

    function run() external {
        l1Router = t1_7683(vm.envAddress("L1_t1_7683_PROXY_ADDR"));
        // Load Alice's private key from env
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        // Start broadcasting as Alice
        vm.startBroadcast(alicePk);

        // Approve tokens
        ERC20 inputToken = ERC20(vm.envAddress("L1_USDT_ADDR"));
        ERC20 outputToken = ERC20(vm.envAddress("L2_USDT_ADDR"));
        inputToken.approve(address(l1Router), type(uint256).max);

        // Prepare order data
        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(alice),
            recipient: TypeCasts.addressToBytes32(alice),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: 100,
            amountOut: 100,
            senderNonce: uint32(
                uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % 10_000
            ), // Random number between 0 and 9999
            originDomain: ORIGIN_CHAIN,
            destinationDomain: DESTINATION_CHAIN,
            destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("L2_t1_7683_PROXY_ADDR")),
            fillDeadline: uint32(block.timestamp + 24 hours),
            data: new bytes(0)
        });

        bytes memory encodedOrder = OrderEncoder.encode(orderData);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(encodedOrder, orderData.fillDeadline, OrderEncoder.orderDataType());

        l1Router.open(order);

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

// Step 2: Solver fills on L2
contract SolverFillScript is Script {
    function run() external {
        uint256 solverPk = vm.envUint("TEST_PRIVATE_KEY");
        address solver = vm.addr(solverPk);

        vm.startBroadcast(solverPk);

        // Get order details
        t1_7683 l2Router = t1_7683(vm.envAddress("L2_t1_7683_PROXY_ADDR"));
        // NOTE - orderId logged from the first step goes here (remove 0x first)
        bytes32 orderId = hex"";

        // NOTE - encodedOrder logged from the first step goes here
        bytes memory originData = hex"";

        // Approve output tokens
        ERC20(vm.envAddress("L2_USDT_ADDR")).approve(
            address(l2Router),
            100 // match amount from order
        );

        // Fill the order
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(solver));
        l2Router.fill(orderId, originData, fillerData);

        vm.stopBroadcast();
    }
}

// Step 3: Settlement and Relay
contract SettlementScript is Script {
    function run() external {
        uint256 settlerPk = vm.envUint("TEST_PRIVATE_KEY");

        vm.startBroadcast(settlerPk);

        t1_7683 l2Router = t1_7683(vm.envAddress("L2_t1_7683_PROXY_ADDR"));

        // Prepare order IDs and filler data for batch settlement
        bytes32[] memory orderIds = new bytes32[](1);
        // NOTE - orderId logged from the first step goes here (remove 0x first)
        orderIds[0] = hex"";

        l2Router.settle{ value: 0 }(orderIds);

        vm.stopBroadcast();
    }
}
