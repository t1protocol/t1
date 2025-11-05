// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { OnchainCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";

import { IT1XChainReader } from "../../libraries/xChain/IT1XChainReader.sol";
import { IT1ERC7683 } from "../../../src/interfaces/IT1ERC7683.sol";
import { T1XChainReader } from "../../libraries/xChain/T1XChainReader.sol";
import { T1XChainReaderBaseTestSetup } from "./T1XChainReaderBaseTestSetup.sol";
import { T1ERC7683 } from "../../7683/T1ERC7683.sol";

contract ClosedAuctionTest is T1XChainReaderBaseTestSetup {
    using TypeCasts for address;

    uint256 batchIndex = 0;
    uint256 position = 0;

    function setUp() public virtual override {
        super.setUp();
        __T1TestBase_setUp();

        // Deploy T1XChainReader on both chains
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
        l1T1ERC7683.initialize(address(l2T1ERC7683), auctionWitness);
        l2T1ERC7683.initialize(address(l1T1ERC7683), auctionWitness);
    }

    function test_fillWithValidAuthorization() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        // Generate EIP-712 authorization signature
        bytes memory authorization = _generateAuthorization(orderId, vegeta, amount, auctionWitnessPK);

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), authorization);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();

        assertEq(uint8(l2T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.FILLED));
    }

    function test_authorizationDataIsIgnoreIfNotClosedAuction() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(false);

        // Not matching authorization signature
        bytes memory authorization = _generateAuthorization(orderId, kakaroto, amount + 1, auctionWitnessPK);

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), authorization);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();

        assertEq(uint8(l2T1ERC7683.orderStatus(orderId)), uint8(IT1ERC7683.Status.FILLED));
    }

    function test_revertIfInvalidAuthorization() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        // Generate invalid authorization by signing with wrong private key (vegeta instead of auctionWitness)
        bytes memory invalidAuthorization = _generateAuthorization(orderId, vegeta, amount, vegetaPK);

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), invalidAuthorization);

        vm.expectRevert(IT1ERC7683.InvalidFillAuthorization.selector);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();
    }

    function test_revertIfNoAuthorization() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta));

        vm.expectRevert();
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();
    }

    function test_revertIfEmptyAuthorization() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        bytes memory malformedAuthorization = abi.encodePacked(bytes32(0));

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), malformedAuthorization);

        vm.expectRevert(IT1ERC7683.InvalidFillAuthorization.selector);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();
    }

    function test_revertIfMalformedAuthorization() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        // Use completely invalid authorization data
        bytes memory malformedAuthorization = hex"deadbeef";

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), malformedAuthorization);

        vm.expectRevert(IT1ERC7683.InvalidFillAuthorization.selector);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();
    }

    function test_revertIfInvalidAmountOut() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        // Generate authorization with an invalid amountOut value
        bytes memory authorization = _generateAuthorization(orderId, vegeta, amount + 1, auctionWitnessPK);

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), authorization);

        vm.expectRevert(IT1ERC7683.InvalidFillAuthorization.selector);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();
    }

    function test_revertIfInvalidOrderId() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        // Generate authorization with an invalid orderId
        bytes32 invalidOrderId = bytes32(vm.randomUint());
        bytes memory authorization = _generateAuthorization(invalidOrderId, vegeta, amount, auctionWitnessPK);

        vm.startPrank(vegeta);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), authorization);

        vm.expectRevert(IT1ERC7683.InvalidFillAuthorization.selector);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();
    }

    function test_revertIfInvalidSolver() public {
        (OrderData memory orderData, bytes32 orderId) = _openOrder(true);

        bytes memory authorization = _generateAuthorization(orderId, vegeta, amount, auctionWitnessPK);

        // Call fill with invalid solver account
        vm.startPrank(kakaroto);
        outputToken.approve(address(l2T1ERC7683), amount);
        bytes memory originData = OrderEncoder.encode(orderData);
        bytes memory fillerData = abi.encode(amount, TypeCasts.addressToBytes32(vegeta), authorization);

        vm.expectRevert(IT1ERC7683.InvalidFillAuthorization.selector);
        l2T1ERC7683.fill(orderId, originData, fillerData);
        vm.stopPrank();
    }

    function _openOrder(bool closedAuction) internal returns (OrderData memory orderData, bytes32 orderId) {
        orderData = _prepareOrderData(amount);
        orderData.closedAuction = closedAuction;
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(l1T1ERC7683), amount);
        vm.recordLogs();
        l1T1ERC7683.open(order);
        vm.stopPrank();

        (bytes32 orderId_,) = _getOrderIDFromLogs();
        assertEq(uint8(l1T1ERC7683.orderStatus(orderId_)), uint8(IT1ERC7683.Status.OPENED));

        return (orderData, orderId_);
    }

    function _generateAuthorization(
        bytes32 orderId,
        address filler,
        uint256 amountOut,
        uint256 signerPK
    )
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(l2T1ERC7683.FILL_AUTHORIZATION_TYPEHASH(), orderId, filler, amountOut));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", l2T1ERC7683.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, digest);

        return abi.encodePacked(r, s, v);
    }
}
