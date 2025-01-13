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
import { IL2T1MessageVerifier } from "../L2/IL2T1MessageVerifier.sol";
import { MockMessengerRecipient } from "./mocks/MockMessengerRecipient.sol";

contract L2T1MessageVerifierTest is DSTestPlus {
    uint64 internal constant ARB_CHAIN_ID = 42_161;

    L1T1Messenger internal l1Messenger;

    address internal postman;
    Whitelist private whitelist;

    L2T1MessageVerifier internal l2MessageVerifier;
    L2T1Messenger internal l2Messenger;
    L2MessageQueue internal l2MessageQueue;
    L1GasPriceOracle internal l1GasOracle;
    L2GasPriceOracle internal l2GasOracle;
    MockMessengerRecipient internal mockMessengerRecipient;

    // 0.1 gwei = 100000000 wei
    uint256 internal l2BaseFee = 100_000_000;
    uint256 internal gasLimit = 21_000;
    uint256 internal value = l2BaseFee * gasLimit;

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
        l2MessageVerifier.initialize(address(l2MessageVerifier), address(l2Messenger));
        l2MessageQueue.setGasOracle(ARB_CHAIN_ID, address(l2GasOracle));
        uint64 _txGas = 21_000;
        uint64 _txGasContractCreation = 32_000;
        uint64 _zeroGas = 4;
        uint64 _nonZeroGas = 16;
        l2GasOracle.initialize(_txGas, _txGasContractCreation, _zeroGas, _nonZeroGas);

        uint64[] memory network = new uint64[](1);
        network[0] = ARB_CHAIN_ID;
        l2Messenger.initialize(address(l1Messenger), network);
        l2Messenger.setVerifier(ARB_CHAIN_ID, address(l2MessageVerifier));
        l2MessageQueue.initialize(address(l2Messenger));
        l1GasOracle.updateWhitelist(address(whitelist));
        l2GasOracle.updateWhitelist(address(whitelist));
        address[] memory _accounts = new address[](1);
        _accounts[0] = address(this);
        whitelist.updateWhitelistStatus(_accounts, true);

        mockMessengerRecipient = new MockMessengerRecipient(IL2T1Messenger(address(l2Messenger)));
        hevm.deal(address(mockMessengerRecipient), 100 ether);

        l2GasOracle.setL2BaseFee(l2BaseFee);
    }

    function testSendMessageCallback() external {
        /// only to cover gas fees on destination chain
        uint256 _valuePlusOne = value + 1;

        hevm.prank(address(mockMessengerRecipient));
        uint256 nonce = mockMessengerRecipient.sendMessage{ value: _valuePlusOne }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );

        bool success = true;
        uint256 bytesNum = 4;
        bytes32 txHash = bytes32(bytesNum);
        string memory bytesStr = "4";
        bytes memory result = bytes(bytesStr);
        // calling as any account other than the owner should revert
        hevm.prank(address(2));
        hevm.expectRevert("Ownable: caller is not the owner");
        l2MessageVerifier.validateCallback(
            ARB_CHAIN_ID, address(mockMessengerRecipient), nonce, success, txHash, value, result
        );

        uint256 callbackAddressBalanceBefore = address(mockMessengerRecipient).balance;
        hevm.expectEmit(true, true, true, true);
        emit MockMessengerRecipient.CallbackReceived(nonce, success, txHash);
        l2MessageVerifier.validateCallback(
            ARB_CHAIN_ID, address(mockMessengerRecipient), nonce, success, txHash, value, result
        );

        uint256 callbackAddressBalanceAfter = address(mockMessengerRecipient).balance;
        assertEq(callbackAddressBalanceAfter - callbackAddressBalanceBefore, 1, "1 wei refund");
    }

    function testSendMessageCallbackTxFailedFullRefund() external {
        hevm.prank(address(mockMessengerRecipient));
        uint256 nonce = mockMessengerRecipient.sendMessage{ value: value }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );

        bool success = false;
        string memory bytesStr = "4";
        bytes32 txHash = bytes32(0);
        bytes memory result = bytes(bytesStr);

        uint256 callbackAddressBalanceBefore = address(mockMessengerRecipient).balance;

        l2MessageVerifier.validateCallback(
            ARB_CHAIN_ID, address(mockMessengerRecipient), nonce, success, txHash, value, result
        );

        uint256 callbackAddressBalanceAfter = address(mockMessengerRecipient).balance;
        assertEq(callbackAddressBalanceAfter - callbackAddressBalanceBefore, value, "full refund");
    }

    function testSendMessageCallbackTxFailedNoGasRefund() external {
        uint256 _valuePlusOne = value + 1;

        hevm.prank(address(mockMessengerRecipient));
        uint256 nonce = mockMessengerRecipient.sendMessage{ value: _valuePlusOne }(
            address(0), 1, new bytes(0), gasLimit, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );

        bool success = false;
        string memory bytesStr = "4";
        /// nonzero tx hash means tx failed on-chain
        uint256 bytesNum = 4;
        bytes32 txHash = bytes32(bytesNum);
        bytes memory result = bytes(bytesStr);

        uint256 callbackAddressBalanceBefore = address(mockMessengerRecipient).balance;

        l2MessageVerifier.validateCallback(
            ARB_CHAIN_ID, address(mockMessengerRecipient), nonce, success, txHash, value, result
        );

        uint256 callbackAddressBalanceAfter = address(mockMessengerRecipient).balance;
        assertEq(callbackAddressBalanceAfter - callbackAddressBalanceBefore, 1, "only value transfer is refunded");
    }

    function testSendMessageCallbackFailsInvalidGasValue() external {
        hevm.prank(address(mockMessengerRecipient));
        uint256 nonce = mockMessengerRecipient.sendMessage{ value: value }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );

        bool success = true;
        string memory bytesStr = "4";
        /// nonzero tx hash means tx failed on-chain
        uint256 bytesNum = 4;
        bytes32 txHash = bytes32(bytesNum);
        bytes memory result = bytes(bytesStr);

        /// actual gas used is more than user supplied
        uint256 _actualGasUsed = value + 1;

        hevm.expectRevert(L2T1MessageVerifier.ActualGasExceedsUserSupplied.selector);
        l2MessageVerifier.validateCallback(
            ARB_CHAIN_ID, address(mockMessengerRecipient), nonce, success, txHash, _actualGasUsed, result
        );
    }

    function testOnlyMessengerCanSetMessageValues() external {
        address mockCaller = address(0xdead);

        // Attempt to call setMessageValues from the mock caller
        hevm.prank(mockCaller);
        hevm.expectRevert(IL2T1MessageVerifier.OnlyMessenger.selector);
        l2MessageVerifier.setMessageValues(0, 0, 0);
    }

    receive() external payable { }
}
