// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { L1GasPriceOracle } from "../L2/predeploys/L1GasPriceOracle.sol";
import { L2GasPriceOracle } from "../L1/rollup/L2GasPriceOracle.sol";
import { L2MessageQueue } from "../L2/predeploys/L2MessageQueue.sol";
import { Whitelist } from "../L2/predeploys/Whitelist.sol";
import { L1T1Messenger } from "../L1/L1T1Messenger.sol";
import { L2T1Messenger } from "../L2/L2T1Messenger.sol";
import { IL2T1Messenger } from "../L2/IL2T1Messenger.sol";
import { L2T1MessageVerifier } from "../L2/L2T1MessageVerifier.sol";
import { MockMessengerRecipient } from "./mocks/MockMessengerRecipient.sol";

import { AddressAliasHelper } from "../libraries/common/AddressAliasHelper.sol";
import { T1Constants } from "../libraries/constants/T1Constants.sol";

contract L2T1MessengerTest is DSTestPlus {
    uint64 internal constant POLYGON_CHAIN_ID = 137;
    uint64 internal constant ARB_CHAIN_ID = 42_161;

    L1T1Messenger internal l1Messenger;

    address internal feeVault;
    Whitelist private whitelist;

    L2T1Messenger internal l2Messenger;
    L2T1MessageVerifier internal l2MessageVerifier;
    L2MessageQueue internal l2MessageQueue;
    L1GasPriceOracle internal l1GasOracle;
    L2GasPriceOracle internal l2GasOracle;
    MockMessengerRecipient internal mockMessengerRecipient;

    function setUp() public {
        // Deploy L1 contracts
        l1Messenger = new L1T1Messenger(address(1), address(1), address(1));

        // Deploy L2 contracts
        whitelist = new Whitelist(address(this));
        l2MessageQueue = new L2MessageQueue(address(this));
        l1GasOracle = new L1GasPriceOracle(address(this));
        l2GasOracle = L2GasPriceOracle(payable(new ERC1967Proxy(address(new L2GasPriceOracle()), new bytes(0))));
        l2Messenger = L2T1Messenger(
            payable(
                new ERC1967Proxy(
                    address(new L2T1Messenger(address(l1Messenger), address(l2MessageQueue))), new bytes(0)
                )
            )
        );
        l2MessageVerifier =
            L2T1MessageVerifier(payable(new ERC1967Proxy(address(new L2T1MessageVerifier()), new bytes(0))));

        // Initialize L2 contracts
        l2MessageVerifier.initialize(address(l2MessageVerifier));

        uint64[] memory network = new uint64[](1);
        network[0] = ARB_CHAIN_ID;
        // Initialize L2 contracts
        l2Messenger.initialize(address(l1Messenger), network);
        l2MessageQueue.initialize(address(l2Messenger));
        l2MessageQueue.setGasOracle(ARB_CHAIN_ID, address(l2GasOracle));
        uint64 _txGas = 21_000;
        uint64 _txGasContractCreation = 32_000;
        uint64 _zeroGas = 4;
        uint64 _nonZeroGas = 16;
        l2GasOracle.initialize(_txGas, _txGasContractCreation, _zeroGas, _nonZeroGas);
        l1GasOracle.updateWhitelist(address(whitelist));
        l2GasOracle.updateWhitelist(address(whitelist));
        address[] memory _accounts = new address[](1);
        _accounts[0] = address(this);
        whitelist.updateWhitelistStatus(_accounts, true);

        mockMessengerRecipient = new MockMessengerRecipient(IL2T1Messenger(address(l2MessageVerifier)));
    }

    function testRelayByCounterparty() external {
        hevm.expectRevert("Caller is not L1T1Messenger");
        l2Messenger.relayMessage(address(this), address(this), 0, 0, new bytes(0));
    }

    function testForbidCallFromL1() external {
        hevm.startPrank(AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger)));
        hevm.expectRevert("Forbid to call message queue");
        l2Messenger.relayMessage(address(this), address(l2MessageQueue), 0, 0, new bytes(0));

        hevm.expectRevert("Forbid to call self");
        l2Messenger.relayMessage(address(this), address(l2Messenger), 0, 0, new bytes(0));
        hevm.stopPrank();
    }

    function testSendMessage(address callbackAddress) external {
        hevm.assume(callbackAddress.code.length == 0);
        hevm.assume(uint256(uint160(callbackAddress)) > 100); // ignore some precompile contracts
        hevm.assume(callbackAddress != address(0x000000000000000000636F6e736F6c652e6c6f67)); // ignore console/console2
        hevm.assume(callbackAddress != address(this));

        // reverts with UnsupportedSenderInterface error if callback address does not implement interface
        hevm.expectRevert(L2T1Messenger.UnsupportedSenderInterface.selector);
        l2Messenger.sendMessage{ value: 1 }(address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID, address(this));

        hevm.deal(address(mockMessengerRecipient), 100 ether);

        hevm.startPrank(address(mockMessengerRecipient));

        // Insufficient msg.value
        hevm.expectRevert(abi.encodeWithSelector(L2T1Messenger.InsufficientMsgValue.selector, 1));
        l2Messenger.sendMessage(address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID);

        hevm.expectRevert(L2T1Messenger.InvalidDestinationChain.selector);
        l2Messenger.sendMessage(address(0), 1, new bytes(0), 21_000, POLYGON_CHAIN_ID, address(mockMessengerRecipient));

        // succeed normally
        uint256 balanceBefore = callbackAddress.balance;
        uint256 nonce = l2Messenger.sendMessage{ value: 1 }(
            address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );
        assertEq(nonce, 0);
        assertEq(balanceBefore, callbackAddress.balance);

        nonce = l2Messenger.sendMessage{ value: 1 }(
            address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );
        assertEq(nonce, 1);

        hevm.stopPrank();
        // 0.1 gwei = 100000000 wei
        uint256 l2BaseFee = 100_000_000;
        uint256 gasLimit = 21_000;
        l2GasOracle.setL2BaseFee(l2BaseFee);

        /// only to cover gas fees on destination chain
        uint256 _value = l2BaseFee * gasLimit;
        nonce = l2Messenger.sendMessage{ value: _value }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );
        assertEq(nonce, 2);

        // failure case - 1 wei short
        uint256 _valueMinusOne = _value - 1;
        hevm.expectRevert(abi.encodeWithSelector(L2T1Messenger.InsufficientMsgValue.selector, _value));
        nonce = l2Messenger.sendMessage{ value: _valueMinusOne }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );
    }

    function testSendMessageRefund() external {
        // 0.1 gwei = 100000000 wei
        uint256 l2BaseFee = 100_000_000;
        uint256 gasLimit = 21_000;
        l2GasOracle.setL2BaseFee(l2BaseFee);

        /// only to cover gas fees on destination chain
        uint256 _value = l2BaseFee * gasLimit;

        // refund case - 1 wei over
        uint256 _balanceThisBefore = address(this).balance;
        uint256 _valuePlusOne = _value + 1;
        l2Messenger.sendMessage{ value: _valuePlusOne }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );

        uint256 _balanceThisAfter = address(this).balance;
        uint256 _balanceCallbackAddressAfter = address(mockMessengerRecipient).balance;
        assertEq(_balanceThisAfter, _balanceThisBefore - _valuePlusOne, "balance of this contract");
        assertEq(_balanceCallbackAddressAfter, 1, "balance of mockMessengerRecipient contract");
    }

    function testAddChain() external {
        uint64 thisChainId = l2Messenger.chainId();

        hevm.expectRevert(L2T1Messenger.CannotSupportCurrentChain.selector);
        l2Messenger.addChain(thisChainId);

        hevm.prank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        l2Messenger.addChain(ARB_CHAIN_ID);

        l2Messenger.addChain(ARB_CHAIN_ID);

        // Ethereum is always supported
        assert(l2Messenger.isSupportedDest(T1Constants.ETH_CHAIN_ID));
        assert(l2Messenger.isSupportedDest(ARB_CHAIN_ID));
        assert(!l2Messenger.isSupportedDest(POLYGON_CHAIN_ID));
    }

    function testRemoveChain() external {
        hevm.prank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        l2Messenger.removeChain(ARB_CHAIN_ID);

        l2Messenger.removeChain(ARB_CHAIN_ID);

        // Ethereum is always supported
        assert(l2Messenger.isSupportedDest(T1Constants.ETH_CHAIN_ID));
        assert(!l2Messenger.isSupportedDest(ARB_CHAIN_ID));
    }
}
