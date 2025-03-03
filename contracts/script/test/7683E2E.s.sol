// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OrderData, OrderEncoder } from "../../src/7683/libs/OrderEncoder.sol";
import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../../src/7683/IERC7683.sol";
import { t1_7683 } from "../../src/7683/t1_7683.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

uint32 constant ORIGIN_CHAIN = uint32(T1Constants.L1_CHAIN_ID);
uint32 constant DESTINATION_CHAIN = uint32(T1Constants.T1_DEVNET_CHAIN_ID);

// Step 1: Setup Alice's account, sign and relay intent
contract AliceSetupScript is Script {
    t1_7683 public L1_ROUTER;

    function run() external {
        L1_ROUTER = t1_7683(vm.envAddress("L1_t1_7683_PROXY_ADDR"));
        // Load Alice's private key from env
        uint256 alicePk = vm.envUint("TEST_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        // Start broadcasting as Alice
        vm.startBroadcast(alicePk);

        // Approve tokens
        ERC20 inputToken = ERC20(vm.envAddress("L1_USDT_ADDR"));
        ERC20 outputToken = ERC20(vm.envAddress("L2_USDT_ADDR"));
        inputToken.approve(address(L1_ROUTER), type(uint256).max);

        // Prepare order data
        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(alice),
            recipient: TypeCasts.addressToBytes32(alice),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: 100,
            amountOut: 100,
            senderNonce: 5,
            originDomain: ORIGIN_CHAIN,
            destinationDomain: DESTINATION_CHAIN,
            destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("L2_t1_7683_PROXY_ADDR")),
            fillDeadline: uint32(block.timestamp + 24 hours),
            data: new bytes(0)
        });

        bytes32 id = OrderEncoder.id(orderData);
        console2.logString("order id");
        console2.logBytes32(id);
        console2.log("fillDeadline", orderData.fillDeadline);

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        L1_ROUTER.open(order);

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
        // TODO - make this not alice
        uint256 solverPk = vm.envUint("TEST_PRIVATE_KEY");
        address solver = vm.addr(solverPk);

        uint256 alicePk = vm.envUint("TEST_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        ERC20 inputToken = ERC20(vm.envAddress("L1_USDT_ADDR"));
        ERC20 outputToken = ERC20(vm.envAddress("L2_USDT_ADDR"));

        vm.startBroadcast(solverPk);

        // Get order details
        t1_7683 l2Router = t1_7683(vm.envAddress("L2_t1_7683_PROXY_ADDR"));
        bytes32 orderId = hex"0b034c1a9f4122ef479330e7a02b355263bcd90802e1415ee83a52f3d0d6cb12";

        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(alice),
            recipient: TypeCasts.addressToBytes32(alice),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: 100,
            amountOut: 100,
            senderNonce: 5,
            originDomain: ORIGIN_CHAIN,
            destinationDomain: DESTINATION_CHAIN,
            destinationSettler: TypeCasts.addressToBytes32(vm.envAddress("L2_t1_7683_PROXY_ADDR")),
            fillDeadline: uint32(1_740_169_380),
            data: new bytes(0)
        });

        bytes memory encodedOrderData = OrderEncoder.encode(orderData);
        OnchainCrossChainOrder memory onchainCrossChainOrder = OnchainCrossChainOrder({
            fillDeadline: orderData.fillDeadline,
            orderDataType: OrderEncoder.orderDataType(),
            orderData: encodedOrderData
        });
        ResolvedCrossChainOrder memory resolvedOrder = l2Router.resolve(onchainCrossChainOrder);

        // Approve output tokens
        ERC20(vm.envAddress("L2_USDT_ADDR")).approve(
            address(l2Router),
            100 // match amount from order
        );

        // Fill the order
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(solver));
        l2Router.fill(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

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
        orderIds[0] = hex"0b034c1a9f4122ef479330e7a02b355263bcd90802e1415ee83a52f3d0d6cb12";

        l2Router.settle{ value: 0 }(orderIds);

        vm.stopBroadcast();
    }
}
