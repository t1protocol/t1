// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OrderData, OrderEncoder } from "../../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../../src/interfaces/IERC7683.sol";
import { T1ERC7683 } from "../../../../src/7683/T1ERC7683.sol";
import { T1Constants } from "../../../../src/libraries/constants/T1Constants.sol";

contract LoadTest is Script {
    T1ERC7683 public l1_7683;

    function run(string memory direction) external {
        // Define chain IDs
        uint32 arbitrumChainId = uint32(T1Constants.ARBITRUM_MAINNET_CHAIN_ID);
        uint32 baseChainId = uint32(T1Constants.BASE_MAINNET_CHAIN_ID);

        // Declare variables to be set based on direction
        uint32 originChain;
        uint32 destinationChain;
        string memory forkUrl;
        address t1ProxyAddr;
        address inputTokenAddr;
        address outputTokenAddr;
        address destinationSettlerAddr;

        // Set chain, token, and proxy addresses based on direction
        if (keccak256(abi.encodePacked(direction)) == keccak256(abi.encodePacked("arb-to-base"))) {
            originChain = arbitrumChainId;
            destinationChain = baseChainId;
            forkUrl = "arbitrum";
            t1ProxyAddr = vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR");
            inputTokenAddr = vm.envAddress("USDC_ARB");
            outputTokenAddr = vm.envAddress("USDC_BASE");
            destinationSettlerAddr = vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR");
        } else if (keccak256(abi.encodePacked(direction)) == keccak256(abi.encodePacked("base-to-arb"))) {
            originChain = baseChainId;
            destinationChain = arbitrumChainId;
            forkUrl = "base";
            t1ProxyAddr = vm.envAddress("BASE_T1_PULL_BASED_7683_PROXY_ADDR");
            inputTokenAddr = vm.envAddress("USDC_BASE");
            outputTokenAddr = vm.envAddress("USDC_ARB");
            destinationSettlerAddr = vm.envAddress("ARB_T1_PULL_BASED_7683_PROXY_ADDR");
        } else {
            revert("Invalid direction: use 'arb-to-base' or 'base-to-arb'");
        }

        // Select the appropriate fork
        vm.createSelectFork(vm.rpcUrl(forkUrl));
        l1_7683 = T1ERC7683(t1ProxyAddr);

        // Load Alice's private key from env
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        address alice = vm.addr(alicePk);

        // Start broadcasting as Alice
        vm.startBroadcast(alicePk);

        // Approve tokens
        ERC20 inputToken = ERC20(inputTokenAddr);
        ERC20 outputToken = ERC20(outputTokenAddr);
        inputToken.approve(address(l1_7683), type(uint256).max);

        // Prepare order data
        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(alice),
            recipient: TypeCasts.addressToBytes32(alice),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: 100, // AMOUNT_IN constant replaced with literal for simplicity
            minAmountOut: 100 * 9 / 10, // 90% of amountIn
            senderNonce: uint32(
                uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % 10_000
            ), // Random number between 0 and 9999
            originDomain: originChain,
            destinationDomain: destinationChain,
            destinationSettler: TypeCasts.addressToBytes32(destinationSettlerAddr),
            fillDeadline: uint32(block.timestamp + 5 minutes),
            closedAuction: true,
            data: new bytes(0)
        });

        // Encode and open order
        bytes memory encodedOrder = OrderEncoder.encode(orderData);
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(encodedOrder, orderData.fillDeadline, OrderEncoder.orderDataType());
        l1_7683.open(order);

        // Log order details
        bytes32 id = OrderEncoder.id(orderData);
        console2.logString("orderId: ");
        console2.logBytes32(id);
        console2.logString("encodedOrder: ");
        console2.logBytes(encodedOrder);

        vm.stopBroadcast();
    }

    function _prepareOnchainOrder(
        bytes memory orderData,
        uint32 fillDeadline,
        bytes32 orderDataType
    ) internal pure returns (OnchainCrossChainOrder memory) {
        return OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: orderDataType,
            orderData: orderData
        });
    }
}