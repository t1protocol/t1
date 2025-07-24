// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";

import {BaseTest} from "./BaseTest.sol";
import {OrderData} from "../../../src/libraries/7683/OrderEncoder.sol";

import {T1ERC7683} from "../../7683/T1ERC7683.sol";
import {T1XChainReader} from "../../libraries/xChain/T1XChainReader.sol";

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

    receive() external payable {}

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
            destinationSettler: address(l2T1ERC7683).addressToBytes32(),
            fillDeadline: uint32(block.timestamp + 100),
            data: new bytes(0)
        });
    }
}
