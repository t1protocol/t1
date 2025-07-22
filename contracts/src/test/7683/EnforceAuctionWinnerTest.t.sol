// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";

import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1XChainReaderBaseTestSetup } from "./T1XChainReaderBaseTestSetup.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";

contract EnforceAuctionWinnerTest is T1XChainReaderBaseTestSetup {
    using TypeCasts for address;

    uint256 batchIndex = 0;
    uint256 position = 0;
    address solver;

    function setUp() public virtual override {
        super.setUp();

        originReader = T1XChainReader(payable(_deployProxy(address(proxyOwner))));
        admin.upgrade(ITransparentUpgradeableProxy(address(originReader)), address(new T1XChainReader(address(this))));
        originReader.initialize(address(this));

        destinationReader = T1XChainReader(payable(_deployProxy(address(proxyOwner))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(destinationReader)), address(new T1XChainReader(address(this)))
        );
        destinationReader.initialize(address(this));

        l1T1ERC7683 = T1ERC7683(payable(_deployProxy(address(proxyOwner))));
        l2T1ERC7683 = T1ERC7683(payable(_deployProxy(address(proxyOwner))));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1T1ERC7683)),
            address(new T1ERC7683(address(0), address(originReader), uint32(origin)))
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2T1ERC7683)),
            address(new T1ERC7683(address(0), address(destinationReader), uint32(destination)))
        );
        l1T1ERC7683.initialize(address(l2T1ERC7683));
        l2T1ERC7683.initialize(address(l1T1ERC7683));
    }

    function test_shouldFillWithCorrectSolver() public {
        solver = vegeta;
        OrderData memory orderData = _prepareOrderData();
        if (solver != address(0)) {
            orderData.data = abi.encode(solver);
        }

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId_,) = _getOrderIDFromLogs();
        assertEq(l1T1ERC7683.orderStatus(orderId_), l1T1ERC7683.OPENED());

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));
        l2T1ERC7683.fill(orderId_, originData, fillerData);
        assertEq(l2T1ERC7683.orderStatus(orderId_), l2T1ERC7683.FILLED());
        vm.stopPrank();
    }

    function test_shouldFillIfNoEnforcedSolver() public {
        solver = address(0);
        OrderData memory orderData = _prepareOrderData();
        if (solver != address(0)) {
            orderData.data = abi.encode(solver);
        }

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId_,) = _getOrderIDFromLogs();
        assertEq(l1T1ERC7683.orderStatus(orderId_), l1T1ERC7683.OPENED());

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));
        l2T1ERC7683.fill(orderId_, originData, fillerData);
        assertEq(l2T1ERC7683.orderStatus(orderId_), l2T1ERC7683.FILLED());
        vm.stopPrank();
    }

    function test_shouldRevertWithIncorrectSolver() public {
        solver = makeAddr("solver");
        OrderData memory orderData = _prepareOrderData();
        if (solver != address(0)) {
            orderData.data = abi.encode(solver);
        }

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId_,) = _getOrderIDFromLogs();
        assertEq(l1T1ERC7683.orderStatus(orderId_), l1T1ERC7683.OPENED());

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectRevert();
        // vm.expectRevert(abi.encodeWithSelector(T1ERC7683.InvalidSolver.selector, solver));
        l2T1ERC7683.fill(orderId_, originData, fillerData);
        vm.stopPrank();
    }
}
