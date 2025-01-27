// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";
import { console } from "forge-std/console.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { L1GasPriceOracle } from "../L2/predeploys/L1GasPriceOracle.sol";
import { L2GasPriceOracle } from "../L1/rollup/L2GasPriceOracle.sol";
import { L2MessageQueue } from "../L2/predeploys/L2MessageQueue.sol";
import { Whitelist } from "../L2/predeploys/Whitelist.sol";
import { L1T1Messenger } from "../L1/L1T1Messenger.sol";
import { L2T1Messenger } from "../L2/L2T1Messenger.sol";

import { AddressAliasHelper } from "../libraries/common/AddressAliasHelper.sol";
import { T1Constants } from "../libraries/constants/T1Constants.sol";

contract L2T1MessengerTest is DSTestPlus {
    uint64 internal constant POLYGON_CHAIN_ID = 137;
    uint64 internal constant ARB_CHAIN_ID = 42_161;

    L1T1Messenger internal l1Messenger;

    address internal feeVault;
    Whitelist private whitelist;

    L2T1Messenger internal l2Messenger;
    L2MessageQueue internal l2MessageQueue;
    L1GasPriceOracle internal l1GasOracle;
    L2GasPriceOracle internal l2GasOracle;
    MockCallbackRecipient internal mockCallbackRecipient;

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

        mockCallbackRecipient = new MockCallbackRecipient();

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
    }

    // TODO reintroduce as a part of
    // https://www.notion.so/t1protocol/
    // Allow-certain-bridge-methods-onchain-to-be-only-called-by-Postman-identity-17b231194dc380799d13f78f1c3a51b1
    function skiptestRelayByCounterparty() external {
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
        // Insufficient msg.value
        hevm.expectRevert(abi.encodeWithSelector(L2T1Messenger.InsufficientMsgValue.selector, 1));
        l2Messenger.sendMessage(address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID, callbackAddress);

        hevm.expectRevert(L2T1Messenger.InvalidDestinationChain.selector);
        l2Messenger.sendMessage(address(0), 1, new bytes(0), 21_000, POLYGON_CHAIN_ID, callbackAddress);

        // succeed normally
        uint256 balanceBefore = callbackAddress.balance;
        uint256 nonce =
            l2Messenger.sendMessage{ value: 1 }(address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID, callbackAddress);
        assertEq(nonce, 0);
        assertEq(balanceBefore, callbackAddress.balance);

        nonce = l2Messenger.sendMessage{ value: 1 }(address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID, callbackAddress);
        assertEq(nonce, 1);

        // 0.1 gwei = 100000000 wei
        uint256 l2BaseFee = 100_000_000;
        uint256 gasLimit = 21_000;
        l2GasOracle.setL2BaseFee(l2BaseFee);

        /// only to cover gas fees on destination chain
        uint256 _value = l2BaseFee * gasLimit;
        nonce = l2Messenger.sendMessage{ value: _value }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, callbackAddress
        );
        assertEq(nonce, 2);

        // failure case - 1 wei short
        uint256 _valueMinusOne = _value - 1;
        hevm.expectRevert(abi.encodeWithSelector(L2T1Messenger.InsufficientMsgValue.selector, _value));
        nonce = l2Messenger.sendMessage{ value: _valueMinusOne }(
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, callbackAddress
        );
    }

    function testSendMessageRefund() external {
        // using mock contract because this test requires a contract to receive ETH
        address callbackAddress = address(mockCallbackRecipient);
        uint256 _balanceCallbackAddressBefore = address(callbackAddress).balance;
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
            address(0), 0, new bytes(0), gasLimit, ARB_CHAIN_ID, callbackAddress
        );

        uint256 _balanceThisAfter = address(this).balance;
        uint256 _balanceCallbackAddressAfter = address(callbackAddress).balance;
        assertEq(_balanceThisAfter, _balanceThisBefore - _valuePlusOne);
        assertEq(_balanceCallbackAddressAfter - _balanceCallbackAddressBefore, 1);
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
        assert(l2Messenger.isSupportedDest(T1Constants.L1_CHAIN_ID));
        assert(l2Messenger.isSupportedDest(ARB_CHAIN_ID));
        assert(!l2Messenger.isSupportedDest(POLYGON_CHAIN_ID));
    }

    function testRemoveChain() external {
        hevm.prank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        l2Messenger.removeChain(ARB_CHAIN_ID);

        l2Messenger.removeChain(ARB_CHAIN_ID);

        // Ethereum is always supported
        assert(l2Messenger.isSupportedDest(T1Constants.L1_CHAIN_ID));
        assert(!l2Messenger.isSupportedDest(ARB_CHAIN_ID));
    }
}

contract MockCallbackRecipient {
    fallback() external payable { }
}
