// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { BaseTest, TestInterchainGasPaymaster } from "./BaseTest.sol";
import { Base7683 } from "../../../src/7683/Base7683.sol";
import { OrderData, OrderEncoder } from "../../../src/libraries/7683/OrderEncoder.sol";
import { GaslessCrossChainOrder } from "../../../src/interfaces/IERC7683.sol";

import { T1ERC7683 } from "../../7683/T1ERC7683.sol";
import { L1MessageQueue } from "../../L1/rollup/L1MessageQueue.sol";
import { L2MessageQueue } from "../../L2/predeploys/L2MessageQueue.sol";
import { L1T1Messenger } from "../../L1/L1T1Messenger.sol";
import { L2T1Messenger } from "../../L2/L2T1Messenger.sol";
import { T1ChainMockBlob } from "../../mocks/T1ChainMockBlob.sol";
import { MockRollupVerifier } from "../mocks/MockRollupVerifier.sol";

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

event Refunded(bytes32 orderId, address receiver);

contract T1BasicSwapE2E is BaseTest {
    event Filled(bytes32 orderId, bytes originData, bytes fillerData);

    using TypeCasts for address;

    L1T1Messenger internal l1t1Messenger;
    L2T1Messenger internal l2t1Messenger;
    L1MessageQueue internal messageQueue;
    L2MessageQueue internal l2MessageQueue;
    T1ChainMockBlob internal rollup;
    MockRollupVerifier internal verifier;

    TestInterchainGasPaymaster internal igp;

    T1ERC7683 internal origin_7683;
    T1ERC7683 internal destination_7683;

    bytes32 internal origin_7683B32;
    bytes32 internal destination_7683B32;
    bytes32 internal destination_7683OverrideB32;

    uint256 gasPaymentQuote;
    uint256 gasPaymentQuoteOverride;
    uint256 internal constant GAS_LIMIT = 60_000;

    address internal owner = makeAddr("owner");
    address internal sender = makeAddr("sender");
    address internal feeVault;

    function _deployProxiedOrigin_7683(L1T1Messenger _messenger, address _owner) internal returns (T1ERC7683) {
        T1ERC7683 implementation = new T1ERC7683(address(_messenger), permit2, origin);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            abi.encodeWithSelector(T1ERC7683.initialize.selector, address(0), address(0), _owner)
        );

        return T1ERC7683(address(proxy));
    }

    function _deployProxiedDestination_7683(
        L2T1Messenger _messenger,
        address _counterpart
    )
        internal
        returns (T1ERC7683)
    {
        T1ERC7683 implementation = new T1ERC7683(address(_messenger), permit2, destination);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation), address(admin), abi.encodeWithSelector(T1ERC7683.initialize.selector, _counterpart)
        );

        return T1ERC7683(address(proxy));
    }

    function labelAccounts() internal {
        vm.label(owner, "Owner");
        vm.label(sender, "Sender");
        vm.label(feeVault, "Fee Vault");
        vm.label(kakaroto, "Kakaroto");
        vm.label(vegeta, "Vegeta");
        vm.label(karpincho, "Karpincho");
        vm.label(address(l1t1Messenger), "l1t1Messenger");
        vm.label(address(l2t1Messenger), "l2t1Messenger");
        vm.label(address(rollup), "rollup");
        vm.label(address(messageQueue), "messageQueue");
        vm.label(address(l2MessageQueue), "l2MessageQueue");
        vm.label(address(origin_7683), "origin_7683");
        vm.label(address(destination_7683), "destination_7683");
    }

    function setUp() public virtual override {
        super.setUp();
        __T1TestBase_setUp();
        onSetup();
    }

    function onSetup() public {
        l1t1Messenger = L1T1Messenger(payable(_deployProxy(address(0))));
        rollup = T1ChainMockBlob(_deployProxy(address(0)));
        messageQueue = L1MessageQueue(_deployProxy(address(0)));
        admin.upgrade(ITransparentUpgradeableProxy(address(messageQueue)), address(new L1MessageQueue()));
        uint256 maxGasLimit = 5_000_000;
        messageQueue.initialize(address(0), maxGasLimit);
        l2MessageQueue = new L2MessageQueue(address(this));
        l2t1Messenger = L2T1Messenger(payable(_deployProxy(address(0))));

        verifier = new MockRollupVerifier();

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2t1Messenger)),
            address(new L2T1Messenger(address(l1t1Messenger), address(l2MessageQueue)))
        );
        l2MessageQueue.initialize(address(l2t1Messenger));

        uint64[] memory network = new uint64[](1);
        network[0] = origin;
        l2t1Messenger.initialize(address(l1t1Messenger), network);

        feeVault = address(uint160(address(this)) - 1);

        // Upgrade the L1T1Messenger implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1t1Messenger)),
            address(new L1T1Messenger(address(l2t1Messenger), address(rollup), address(messageQueue)))
        );
        l1t1Messenger.initialize(feeVault);

        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(new T1ChainMockBlob(1233, address(messageQueue), address(verifier)))
        );
        rollup.initialize(44);

        igp = new TestInterchainGasPaymaster();

        gasPaymentQuote = igp.quoteGasPayment(destination, GAS_LIMIT);

        origin_7683 = _deployProxiedOrigin_7683(l1t1Messenger, owner);

        _base7683 = Base7683(address(origin_7683));

        destination_7683 = _deployProxiedDestination_7683(l2t1Messenger, address(origin_7683));

        origin_7683B32 = TypeCasts.addressToBytes32(address(origin_7683));
        destination_7683B32 = TypeCasts.addressToBytes32(address(destination_7683));

        balanceId[address(origin_7683)] = 4;
        balanceId[address(destination_7683)] = 5;
        balanceId[address(igp)] = 6;

        users.push(address(origin_7683));
        users.push(address(destination_7683));
        users.push(address(igp));

        vm.stopPrank();

        labelAccounts();
    }

    receive() external payable { }

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
            destinationSettler: address(destination_7683).addressToBytes32(),
            fillDeadline: uint32(block.timestamp + 100),
            data: new bytes(0)
        });
    }

    function _prepareGaslessOrder(
        bytes memory orderData,
        uint256 permitNonce,
        uint32 openDeadline,
        uint32 fillDeadline
    )
        internal
        view
        returns (GaslessCrossChainOrder memory)
    {
        return _prepareGaslessOrder(
            address(origin_7683),
            kakaroto,
            uint64(origin),
            orderData,
            permitNonce,
            openDeadline,
            fillDeadline,
            OrderEncoder.orderDataType()
        );
    }
}
