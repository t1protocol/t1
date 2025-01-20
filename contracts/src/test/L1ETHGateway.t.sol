// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { L1GatewayRouter } from "../L1/gateways/L1GatewayRouter.sol";
import { IL1ETHGateway, L1ETHGateway } from "../L1/gateways/L1ETHGateway.sol";
import { IL1T1Messenger } from "../L1/IL1T1Messenger.sol";
import { IL2ETHGateway, L2ETHGateway } from "../L2/gateways/L2ETHGateway.sol";
import { AddressAliasHelper } from "../libraries/common/AddressAliasHelper.sol";
import { T1Constants } from "../libraries/constants/T1Constants.sol";

import { L1GatewayTestBase } from "./L1GatewayTestBase.t.sol";
import { MockT1Messenger } from "./mocks/MockT1Messenger.sol";
import { MockGatewayRecipient } from "./mocks/MockGatewayRecipient.sol";

contract L1ETHGatewayTest is L1GatewayTestBase {
    // from L1ETHGateway
    event DepositETH(address indexed from, address indexed to, uint256 amount, bytes data);
    event FinalizeWithdrawETH(address indexed from, address indexed to, uint256 amount, bytes data);
    event RefundETH(address indexed recipient, uint256 amount);

    L1ETHGateway private gateway;
    L1GatewayRouter private router;

    L2ETHGateway private counterpartGateway;

    function setUp() public {
        __L1GatewayTestBase_setUp();

        // Deploy L2 contracts
        counterpartGateway = new L2ETHGateway(address(1), address(1), address(1));

        // Deploy L1 contracts
        router = L1GatewayRouter(_deployProxy(address(new L1GatewayRouter())));
        gateway = _deployGateway(address(l1Messenger));

        // Initialize L1 contracts
        gateway.initialize();
        router.initialize(address(gateway), address(0));
    }

    function testInitialized() public {
        assertEq(address(counterpartGateway), gateway.counterpart());
        assertEq(address(router), gateway.router());
        assertEq(address(l1Messenger), gateway.messenger());

        hevm.expectRevert("Initializable: contract is already initialized");
        gateway.initialize();
    }

    function testDepositETH(uint256 amount, uint256 gasLimit, uint256 feePerGas) public {
        _depositETH(false, amount, gasLimit, feePerGas);
    }

    function testDepositETHWithRecipient(
        uint256 amount,
        address recipient,
        uint256 gasLimit,
        uint256 feePerGas
    )
        public
    {
        _depositETHWithRecipient(false, amount, recipient, gasLimit, feePerGas);
    }

    function testDepositETHWithRecipientAndCalldata(
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    )
        public
    {
        _depositETHWithRecipientAndCalldata(false, amount, recipient, dataToCall, gasLimit, feePerGas);
    }

    function testRouterDepositETH(uint256 amount, uint256 gasLimit, uint256 feePerGas) public {
        _depositETH(true, amount, gasLimit, feePerGas);
    }

    function testRouterDepositETHWithRecipient(
        uint256 amount,
        address recipient,
        uint256 gasLimit,
        uint256 feePerGas
    )
        public
    {
        _depositETHWithRecipient(true, amount, recipient, gasLimit, feePerGas);
    }

    function testRouterDepositETHWithRecipientAndCalldata(
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    )
        public
    {
        _depositETHWithRecipientAndCalldata(true, amount, recipient, dataToCall, gasLimit, feePerGas);
    }

    // TODO reintrodcuce as a part of
    // https://www.notion.so/t1protocol/
    // Allow-certain-bridge-methods-onchain-to-be-only-called-by-Postman-identity-17b231194dc380799d13f78f1c3a51b1
    //    function testDropMessageMocking() public {
    //        MockT1Messenger mockMessenger = new MockT1Messenger();
    //        gateway = _deployGateway(address(mockMessenger));
    //        gateway.initialize();
    //
    //        // only messenger can call, revert
    //        hevm.expectRevert(ErrorCallerIsNotMessenger.selector);
    //        gateway.onDropMessage(new bytes(0));
    //
    //        // only called in drop context, revert
    //        hevm.expectRevert(ErrorNotInDropMessageContext.selector);
    //        mockMessenger.callTarget(address(gateway), abi.encodeWithSelector(gateway.onDropMessage.selector, new
    // bytes(0)));
    //
    //        mockMessenger.setXDomainMessageSender(T1Constants.DROP_XDOMAIN_MESSAGE_SENDER);
    //
    //        // invalid selector, revert
    //        hevm.expectRevert("invalid selector");
    //        mockMessenger.callTarget(address(gateway), abi.encodeWithSelector(gateway.onDropMessage.selector, new
    // bytes(4)));
    //
    //        bytes memory message = abi.encodeWithSelector(
    //            IL2ETHGateway.finalizeDepositETH.selector, address(this), address(this), 100, new bytes(0)
    //        );
    //
    //        // msg.value mismatch, revert
    //        hevm.expectRevert("msg.value mismatch");
    //        mockMessenger.callTarget{ value: 99 }(
    //            address(gateway), abi.encodeWithSelector(gateway.onDropMessage.selector, message)
    //        );
    //    }

    function testDropMessage(uint256 amount, address recipient, bytes memory dataToCall) public {
        amount = bound(amount, 1, address(this).balance);
        bytes memory message = abi.encodeWithSelector(
            IL2ETHGateway.finalizeDepositETH.selector, address(this), recipient, amount, dataToCall
        );
        gateway.depositETHAndCall{ value: amount }(recipient, amount, dataToCall, DEFAULT_GAS_LIMIT);

        // skip message 0
        hevm.startPrank(address(rollup));
        messageQueue.popCrossDomainMessage(0, 1, 0x1);
        messageQueue.finalizePoppedCrossDomainMessage(1);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 1);
        assertEq(messageQueue.pendingQueueIndex(), 1);
        hevm.stopPrank();

        // ETH transfer failed, revert
        revertOnReceive = true;
        hevm.expectRevert("ETH transfer failed");
        l1Messenger.dropMessage(address(gateway), address(counterpartGateway), amount, 0, message);

        // drop message 0
        hevm.expectEmit(true, true, false, true);
        emit RefundETH(address(this), amount);

        revertOnReceive = false;
        uint256 balance = address(this).balance;
        l1Messenger.dropMessage(address(gateway), address(counterpartGateway), amount, 0, message);
        assertEq(balance + amount, address(this).balance);
    }

    // TODO reintrodcuce as a part of
    // https://www.notion.so/t1protocol/
    // Allow-certain-bridge-methods-onchain-to-be-only-called-by-Postman-identity-17b231194dc380799d13f78f1c3a51b1
    //    function testFinalizeWithdrawETHFailedMocking(
    //        address sender,
    //        address recipient,
    //        uint256 amount,
    //        bytes memory dataToCall
    //    )
    //        public
    //    {
    //        amount = bound(amount, 1, address(this).balance / 2);
    //
    //        // revert when caller is not messenger
    //        hevm.expectRevert(ErrorCallerIsNotMessenger.selector);
    //        gateway.finalizeWithdrawETH(sender, recipient, amount, dataToCall);
    //
    //        MockT1Messenger mockMessenger = new MockT1Messenger();
    //        gateway = _deployGateway(address(mockMessenger));
    //        gateway.initialize();
    //
    //        // only call by counterpart
    //        hevm.expectRevert(ErrorCallerIsNotCounterpartGateway.selector);
    //        mockMessenger.callTarget(
    //            address(gateway),
    //            abi.encodeWithSelector(gateway.finalizeWithdrawETH.selector, sender, recipient, amount, dataToCall)
    //        );
    //
    //        mockMessenger.setXDomainMessageSender(address(counterpartGateway));
    //
    //        // msg.value mismatch
    //        hevm.expectRevert("msg.value mismatch");
    //        mockMessenger.callTarget(
    //            address(gateway),
    //            abi.encodeWithSelector(gateway.finalizeWithdrawETH.selector, sender, recipient, amount, dataToCall)
    //        );
    //
    //        // ETH transfer failed
    //        revertOnReceive = true;
    //        hevm.expectRevert("ETH transfer failed");
    //        mockMessenger.callTarget{ value: amount }(
    //            address(gateway),
    //            abi.encodeWithSelector(gateway.finalizeWithdrawETH.selector, sender, address(this), amount,
    // dataToCall)
    //        );
    //    }

    // TODO reintroduce when doing relayMessageWithProof
    //    function testFinalizeWithdrawETHFailed(
    //        address sender,
    //        address recipient,
    //        uint256 amount,
    //        bytes memory dataToCall
    //    )
    //        public
    //    {
    //        amount = bound(amount, 1, address(this).balance / 2);
    //
    //        // deposit some ETH to L1T1Messenger
    //        gateway.depositETH{ value: amount }(amount, DEFAULT_GAS_LIMIT);
    //
    //        // do finalize withdraw eth
    //        bytes memory message =
    //            abi.encodeWithSelector(IL1ETHGateway.finalizeWithdrawETH.selector, sender, recipient, amount,
    // dataToCall);
    //        bytes memory xDomainCalldata = abi.encodeWithSignature(
    //            "relayMessage(address,address,uint256,uint256,bytes)",
    //            address(uint160(address(counterpartGateway)) + 1),
    //            address(gateway),
    //            amount,
    //            0,
    //            message
    //        );
    //
    //        prepareL2MessageRoot(keccak256(xDomainCalldata));
    //
    //        // IL1T1Messenger.L2MessageProof memory proof;
    //        // proof.batchIndex = rollup.lastFinalizedBatchIndex();
    //
    //        // counterpart is not L2ETHGateway
    //        // emit FailedRelayedMessage from L1T1Messenger
    //        hevm.expectEmit(true, false, false, true);
    //        emit FailedRelayedMessage(keccak256(xDomainCalldata));
    //
    //        uint256 messengerBalance = address(l1Messenger).balance;
    //        uint256 recipientBalance = recipient.balance;
    //        assertBoolEq(false, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
    //        // l1Messenger.relayMessageWithProof(
    //        //     address(uint160(address(counterpartGateway)) + 1), address(gateway), amount, 0, message, proof
    //        // );
    //        l1Messenger.relayMessageWithProof(
    //            address(uint160(address(counterpartGateway)) + 1), address(gateway), amount, 0, message
    //        );
    //        assertEq(messengerBalance, address(l1Messenger).balance);
    //        assertEq(recipientBalance, recipient.balance);
    //        assertBoolEq(false, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
    //    }

    function testFinalizeWithdrawETH(address sender, uint256 amount, bytes memory dataToCall) public {
        MockGatewayRecipient recipient = new MockGatewayRecipient();

        amount = bound(amount, 1, address(this).balance / 2);

        // deposit some ETH to L1T1Messenger
        gateway.depositETH{ value: amount }(amount, DEFAULT_GAS_LIMIT);

        // do finalize withdraw eth
        bytes memory message = abi.encodeWithSelector(
            IL1ETHGateway.finalizeWithdrawETH.selector, sender, address(recipient), amount, dataToCall
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(counterpartGateway),
            address(gateway),
            amount,
            0,
            message
        );

        prepareL2MessageRoot(keccak256(xDomainCalldata));

        // IL1T1Messenger.L2MessageProof memory proof;
        // proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // emit FinalizeWithdrawETH from L1ETHGateway
        {
            hevm.expectEmit(true, true, false, true);
            emit FinalizeWithdrawETH(sender, address(recipient), amount, dataToCall);
        }

        // emit RelayedMessage from L1T1Messenger
        {
            hevm.expectEmit(true, false, false, true);
            emit RelayedMessage(keccak256(xDomainCalldata));
        }

        uint256 messengerBalance = address(l1Messenger).balance;
        uint256 recipientBalance = address(recipient).balance;
        assertBoolEq(false, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
        // l1Messenger.relayMessageWithProof(address(counterpartGateway), address(gateway), amount, 0, message, proof);
        l1Messenger.relayMessageWithProof(address(counterpartGateway), address(gateway), amount, 0, message);
        assertEq(messengerBalance - amount, address(l1Messenger).balance);
        assertEq(recipientBalance + amount, address(recipient).balance);
        assertBoolEq(true, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
    }

    function _depositETH(bool useRouter, uint256 amount, uint256 gasLimit, uint256 feePerGas) private {
        amount = bound(amount, 0, address(this).balance / 2);
        gasLimit = bound(gasLimit, DEFAULT_GAS_LIMIT / 2, DEFAULT_GAS_LIMIT);
        feePerGas = bound(feePerGas, 0, 1000);

        messageQueue.setL2BaseFee(feePerGas);

        uint256 feeToPay = feePerGas * gasLimit;
        bytes memory message = abi.encodeWithSelector(
            IL2ETHGateway.finalizeDepositETH.selector, address(this), address(this), amount, new bytes(0)
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            amount,
            0,
            message
        );

        if (amount == 0) {
            hevm.expectRevert("deposit zero eth");
            if (useRouter) {
                router.depositETH{ value: amount }(amount, gasLimit);
            } else {
                gateway.depositETH{ value: amount }(amount, gasLimit);
            }
        } else {
            // emit QueueTransaction from L1MessageQueue
            {
                hevm.expectEmit(true, true, false, true);
                address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
                emit QueueTransaction(sender, address(l2Messenger), 0, 0, gasLimit, xDomainCalldata);
            }

            // emit SentMessage from L1T1Messenger
            {
                hevm.expectEmit(true, true, false, true);
                emit SentMessage(
                    address(gateway),
                    address(counterpartGateway),
                    amount,
                    0,
                    gasLimit,
                    message,
                    T1Constants.T1_DEVNET_CHAIN_ID
                );
            }

            // emit DepositETH from L1ETHGateway
            hevm.expectEmit(true, true, false, true);
            emit DepositETH(address(this), address(this), amount, new bytes(0));

            uint256 messengerBalance = address(l1Messenger).balance;
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            if (useRouter) {
                router.depositETH{ value: amount + feeToPay + EXTRA_VALUE }(amount, gasLimit);
            } else {
                gateway.depositETH{ value: amount + feeToPay + EXTRA_VALUE }(amount, gasLimit);
            }
            assertEq(amount + messengerBalance, address(l1Messenger).balance);
            assertEq(feeToPay + feeVaultBalance, address(feeVault).balance);
            assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        }
    }

    function _depositETHWithRecipient(
        bool useRouter,
        uint256 amount,
        address recipient,
        uint256 gasLimit,
        uint256 feePerGas
    )
        private
    {
        amount = bound(amount, 0, address(this).balance / 2);
        gasLimit = bound(gasLimit, DEFAULT_GAS_LIMIT / 2, DEFAULT_GAS_LIMIT);
        feePerGas = bound(feePerGas, 0, 1000);

        messageQueue.setL2BaseFee(feePerGas);

        uint256 feeToPay = feePerGas * gasLimit;
        bytes memory message = abi.encodeWithSelector(
            IL2ETHGateway.finalizeDepositETH.selector, address(this), recipient, amount, new bytes(0)
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            amount,
            0,
            message
        );

        if (amount == 0) {
            hevm.expectRevert("deposit zero eth");
            if (useRouter) {
                router.depositETH{ value: amount }(recipient, amount, gasLimit);
            } else {
                gateway.depositETH{ value: amount }(recipient, amount, gasLimit);
            }
        } else {
            // emit QueueTransaction from L1MessageQueue
            {
                hevm.expectEmit(true, true, false, true);
                address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
                emit QueueTransaction(sender, address(l2Messenger), 0, 0, gasLimit, xDomainCalldata);
            }

            // emit SentMessage from L1T1Messenger
            {
                hevm.expectEmit(true, true, false, true);
                emit SentMessage(
                    address(gateway),
                    address(counterpartGateway),
                    amount,
                    0,
                    gasLimit,
                    message,
                    T1Constants.T1_DEVNET_CHAIN_ID
                );
            }

            // emit DepositETH from L1ETHGateway
            hevm.expectEmit(true, true, false, true);
            emit DepositETH(address(this), recipient, amount, new bytes(0));

            uint256 messengerBalance = address(l1Messenger).balance;
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            if (useRouter) {
                router.depositETH{ value: amount + feeToPay + EXTRA_VALUE }(recipient, amount, gasLimit);
            } else {
                gateway.depositETH{ value: amount + feeToPay + EXTRA_VALUE }(recipient, amount, gasLimit);
            }
            assertEq(amount + messengerBalance, address(l1Messenger).balance);
            assertEq(feeToPay + feeVaultBalance, address(feeVault).balance);
            assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        }
    }

    function _depositETHWithRecipientAndCalldata(
        bool useRouter,
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    )
        private
    {
        amount = bound(amount, 0, address(this).balance / 2);
        gasLimit = bound(gasLimit, DEFAULT_GAS_LIMIT / 2, DEFAULT_GAS_LIMIT);
        feePerGas = bound(feePerGas, 0, 1000);

        messageQueue.setL2BaseFee(feePerGas);

        uint256 feeToPay = feePerGas * gasLimit;
        bytes memory message = abi.encodeWithSelector(
            IL2ETHGateway.finalizeDepositETH.selector, address(this), recipient, amount, dataToCall
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            amount,
            0,
            message
        );

        if (amount == 0) {
            hevm.expectRevert("deposit zero eth");
            if (useRouter) {
                router.depositETHAndCall{ value: amount }(recipient, amount, dataToCall, gasLimit);
            } else {
                gateway.depositETHAndCall{ value: amount }(recipient, amount, dataToCall, gasLimit);
            }
        } else {
            // emit QueueTransaction from L1MessageQueue
            {
                hevm.expectEmit(true, true, false, true);
                address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
                emit QueueTransaction(sender, address(l2Messenger), 0, 0, gasLimit, xDomainCalldata);
            }

            // emit SentMessage from L1T1Messenger
            {
                hevm.expectEmit(true, true, false, true);
                emit SentMessage(
                    address(gateway),
                    address(counterpartGateway),
                    amount,
                    0,
                    gasLimit,
                    message,
                    T1Constants.T1_DEVNET_CHAIN_ID
                );
            }

            // emit DepositETH from L1ETHGateway
            hevm.expectEmit(true, true, false, true);
            emit DepositETH(address(this), recipient, amount, dataToCall);

            uint256 messengerBalance = address(l1Messenger).balance;
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            if (useRouter) {
                router.depositETHAndCall{ value: amount + feeToPay + EXTRA_VALUE }(
                    recipient, amount, dataToCall, gasLimit
                );
            } else {
                gateway.depositETHAndCall{ value: amount + feeToPay + EXTRA_VALUE }(
                    recipient, amount, dataToCall, gasLimit
                );
            }
            assertEq(amount + messengerBalance, address(l1Messenger).balance);
            assertEq(feeToPay + feeVaultBalance, address(feeVault).balance);
            assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        }
    }

    function _deployGateway(address messenger) internal returns (L1ETHGateway _gateway) {
        _gateway = L1ETHGateway(_deployProxy(address(0)));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(_gateway)),
            address(new L1ETHGateway(address(counterpartGateway), address(router), address(messenger)))
        );
    }
}
