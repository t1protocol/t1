// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ISignatureTransfer} from "@uniswap/permit2/src/interfaces/IPermit2.sol";

import {BaseTest} from "./BaseTest.sol";
import {T1XChainReader} from "../../libraries/xChain/T1XChainReader.sol";
import {T1ERC7683} from "../../7683/T1ERC7683.sol";
import {OrderData, OrderEncoder} from "../../../src/libraries/7683/OrderEncoder.sol";
import {
    OnchainCrossChainOrder,
    GaslessCrossChainOrder,
    ResolvedCrossChainOrder
} from "../../../src/interfaces/IERC7683.sol";

contract TvlThresholdTest is BaseTest {
    using TypeCasts for address;
    using TypeCasts for bytes32;

    event Paused(address account);
    event Unpaused(address account);

    T1XChainReader internal reader;
    T1ERC7683 internal t1ERC7683;

    function setUp() public virtual override {
        super.setUp();
        __T1TestBase_setUp();

        reader = T1XChainReader(payable(_deployProxy(address(0))));
        admin.upgrade(ITransparentUpgradeableProxy(address(reader)), address(new T1XChainReader(address(this))));

        t1ERC7683 = T1ERC7683(payable(_deployProxy(address(0))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(t1ERC7683)),
            address(new T1ERC7683(permit2, address(reader), uint32(origin)))
        );
        t1ERC7683.initialize(address(t1ERC7683));
    }

    function test_pauseAndUnpause() public {
        // Test that only owner can pause
        vm.prank(address(0xbeef));
        vm.expectRevert("Ownable: caller is not the owner");
        t1ERC7683.pause();

        // Test pause by owner
        t1ERC7683.pause();
        assertTrue(t1ERC7683.paused(), "Contract should be paused");

        // Test that only owner can unpause
        vm.prank(address(0xbeef));
        vm.expectRevert("Ownable: caller is not the owner");
        t1ERC7683.unpause();

        // Test unpause by owner
        t1ERC7683.unpause();
        assertFalse(t1ERC7683.paused(), "Contract should be unpaused");
    }

    function test_pauseAndUnpauseEvents() public {
        // Test pause event
        vm.expectEmit(true, true, true, true);
        emit Paused(address(this));
        t1ERC7683.pause();

        // Test unpause event
        vm.expectEmit(true, true, true, true);
        emit Unpaused(address(this));
        t1ERC7683.unpause();
    }

    function test_canOpenWhenNotPaused() public {
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(t1ERC7683), type(uint256).max);
        t1ERC7683.open(order);
        vm.stopPrank();

        bytes32 orderId = OrderEncoder.id(orderData);
        bytes32 status = t1ERC7683.orderStatus(orderId);
        assertEq(status, t1ERC7683.OPENED());
    }

    function test_canOpenForWhenNotPaused() public {
        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        uint32 openDeadline = uint32(block.timestamp + 100);
        OrderData memory orderData = _prepareOrderData();
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(
            address(t1ERC7683),
            kakaroto,
            orderData.originDomain,
            OrderEncoder.encode(orderData),
            orderData.senderNonce,
            openDeadline,
            orderData.fillDeadline,
            OrderEncoder.orderDataType()
        );
        bytes memory originFillerData = new bytes(0);

        ResolvedCrossChainOrder memory resolvedOrder = t1ERC7683.resolveFor(order, originFillerData);
        bytes memory sig = _getSignature(
            address(t1ERC7683),
            t1ERC7683.witnessHash(resolvedOrder),
            orderData.inputToken.bytes32ToAddress(),
            order.nonce,
            orderData.amountIn,
            openDeadline,
            kakarotoPK
        );

        vm.prank(vegeta);
        t1ERC7683.openFor(order, sig, new bytes(0));

        bytes32 orderId = OrderEncoder.id(orderData);
        bytes32 status = t1ERC7683.orderStatus(orderId);
        assertEq(status, t1ERC7683.OPENED());
    }

    function test_cannotOpenWhenPaused() public {
        t1ERC7683.pause();

        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(t1ERC7683), type(uint256).max);
        vm.expectRevert("Pausable: paused");
        t1ERC7683.open(order);
        vm.stopPrank();
    }

    function test_cannotOpenForWhenPaused() public {
        t1ERC7683.pause();

        OrderData memory orderData = _prepareOrderData();
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(
            address(t1ERC7683),
            kakaroto,
            uint64(origin),
            OrderEncoder.encode(orderData),
            1, // permitNonce
            uint32(block.timestamp + 100), // openDeadline
            orderData.fillDeadline,
            OrderEncoder.orderDataType()
        );

        vm.startPrank(kakaroto);
        inputToken.approve(address(t1ERC7683), type(uint256).max);
        vm.expectRevert("Pausable: paused");
        t1ERC7683.openFor(order, "", "");
        vm.stopPrank();
    }

    function _prepareOrderData() internal view returns (OrderData memory) {
        return OrderData({
            sender: TypeCasts.addressToBytes32(kakaroto),
            recipient: TypeCasts.addressToBytes32(karpincho),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: amount,
            amountOut: amount,
            senderNonce: 1,
            originDomain: origin,
            destinationDomain: destination,
            destinationSettler: address(t1ERC7683).addressToBytes32(),
            fillDeadline: uint32(block.timestamp + 1 hours),
            data: new bytes(0)
        });
    }
}
