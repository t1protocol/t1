// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { BaseTest } from "./BaseTest.sol";
import { OrderData } from "../../../src/libraries/7683/OrderEncoder.sol";

import { T1ERC7683 } from "../../7683/T1ERC7683.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";
import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

event Refunded(bytes32 orderId, address receiver);

contract T1XChainReaderBaseTestSetup is BaseTest {
    event Filled(bytes32 orderId, bytes originData, bytes fillerData);

    using TypeCasts for address;

    T1XChainReader internal originReader;
    T1XChainReader internal destinationReader;
    T1ERC7683 internal l1T1ERC7683;
    T1ERC7683 internal l2T1ERC7683;

    address internal owner = makeAddr("owner");
    address internal sender = makeAddr("sender");
    address internal feeVault;

    function labelAccounts() internal {
        vm.label(owner, "Owner");
        vm.label(sender, "Sender");
        vm.label(feeVault, "Fee Vault");
        vm.label(kakaroto, "Kakaroto");
        vm.label(vegeta, "Vegeta");
        vm.label(karpincho, "Karpincho");
    }

    function setUp() public virtual override {
        super.setUp();
        __T1TestBase_setUp();
        onSetup();
    }

    function onSetup() public {
        feeVault = address(uint160(address(this)) - 1);
        labelAccounts();
    }

    receive() external payable { }

    function _openAndFillOrder() internal virtual returns (OrderData memory, bytes32 orderId, bytes32 requestId) {
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId_,) = _getOrderIDFromLogs();
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId_)), uint8(IT1ERC7683.Status.OPENED));

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta));
        l2T1ERC7683.fill(orderId_, originData, fillerData);
        assertEq(uint8(l2T1ERC7683.orderStatus(orderId_)), uint8(IT1ERC7683.Status.FILLED));
        vm.stopPrank();

        vm.startPrank(vegeta);
        bytes32 requestId_ = l1T1ERC7683.verifySettlement(destination, orderId_);
        vm.stopPrank();

        return (orderData, orderId_, requestId_);
    }

    function _prepareOrderData() internal view virtual returns (OrderData memory) {
        return OrderData({
            sender: TypeCasts.addressToBytes32(kakaroto),
            recipient: TypeCasts.addressToBytes32(karpincho),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: amount,
            minAmountOut: amount,
            senderNonce: 1,
            originDomain: origin,
            destinationDomain: destination,
            destinationSettler: address(l2T1ERC7683).addressToBytes32(),
            fillDeadline: uint32(block.timestamp + 100),
            closedAuction: false,
            data: new bytes(0)
        });
    }

    /// @dev Generate a merkle tree with depth 2 (4 leaves) including the result value and a proof
    /// @param requestId Proof of read request id
    /// @param result Result of the read
    /// @param position position of the leaf where result is stored (0-3)
    /// @return root Root of the merkle tree
    /// @return proof Proof of for the leaf where result is stored
    function _generateMerkleTree(
        bytes32 requestId,
        bytes memory result,
        uint256 position
    )
        internal
        pure
        returns (bytes32 root, bytes memory proof)
    {
        require(position < 4, "position must be < 4 for depth 2 tree");

        // Generate 4 leaves, one for the result and three for the mock leaves
        bytes32[] memory leafs = new bytes32[](4);
        for (uint256 i = 0; i < leafs.length; i++) {
            if (i == position) {
                bytes32 xChainReadResultHash = keccak256(result);
                // Use abi.encodePacked to match T1ERC7683.sol line 138
                leafs[i] = keccak256(abi.encodePacked(xChainReadResultHash, requestId));
            } else {
                bytes32 mockLeaf = keccak256(abi.encodePacked("mock_leaf", i));
                leafs[i] = mockLeaf;
            }
        }

        // Build intermediate nodes
        bytes32[] memory level1 = new bytes32[](2);
        level1[0] = _efficientHash(leafs[0], leafs[1]);
        level1[1] = _efficientHash(leafs[2], leafs[3]);

        root = _efficientHash(level1[0], level1[1]);

        // Generate proof for the target leaf at position position
        bytes32[] memory proofElements = new bytes32[](2);
        uint256 currentposition = position;

        // Leaf sibling
        if (currentposition % 2 == 0) {
            proofElements[0] = leafs[currentposition + 1];
        } else {
            proofElements[0] = leafs[currentposition - 1];
        }
        currentposition /= 2;

        // Intermediate node sibling
        if (currentposition % 2 == 0) {
            proofElements[1] = level1[currentposition + 1];
        } else {
            proofElements[1] = level1[currentposition - 1];
        }

        // Encode proof as concatenated bytes32 values (WithdrawTrieVerifier expects this format)
        proof = new bytes(64); // 2 * 32 bytes
        assembly {
            mstore(add(proof, 0x20), mload(add(proofElements, 0x20)))
            mstore(add(proof, 0x40), mload(add(proofElements, 0x40)))
        }
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
