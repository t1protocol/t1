// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { L1GasPriceOracle } from "../L2/predeploys/L1GasPriceOracle.sol";
import { L2MessageQueue } from "../L2/predeploys/L2MessageQueue.sol";
import { Whitelist } from "../L2/predeploys/Whitelist.sol";
import { L1T1Messenger } from "../L1/L1T1Messenger.sol";
import { L2T1Messenger } from "../L2/L2T1Messenger.sol";
import { IL2T1Messenger } from "../L2/IL2T1Messenger.sol";
import { L2T1MessageVerifier } from "../L2/L2T1MessageVerifier.sol";
import { MockMessengerRecipient } from "./mocks/MockMessengerRecipient.sol";

contract L2T1MessageVerifierTest is DSTestPlus {
    uint64 internal constant ARB_CHAIN_ID = 42_161;

    L1T1Messenger internal l1Messenger;

    address internal feeVault;
    Whitelist private whitelist;

    L2T1MessageVerifier internal l2MessageVerifier;
    L2T1Messenger internal l2Messenger;
    L2MessageQueue internal l2MessageQueue;
    L1GasPriceOracle internal l1GasOracle;

    function setUp() public {
        // Deploy L1 contracts
        l1Messenger = new L1T1Messenger(address(1), address(1), address(1));

        // Deploy L2 contracts
        whitelist = new Whitelist(address(this));
        l2MessageQueue = new L2MessageQueue(address(this));
        l1GasOracle = new L1GasPriceOracle(address(this));
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
        l2Messenger.initialize(address(l1Messenger), network);
        l2Messenger.setVerifier(ARB_CHAIN_ID, address(l2MessageVerifier));
        l2MessageQueue.initialize(address(l2Messenger));
        l1GasOracle.updateWhitelist(address(whitelist));
    }

    function testSendMessageCallback() external {
        MockMessengerRecipient mockMessengerRecipient = new MockMessengerRecipient(IL2T1Messenger(address(l2Messenger)));
        hevm.deal(address(mockMessengerRecipient), 100 ether);

        hevm.prank(address(mockMessengerRecipient));
        uint256 nonce = mockMessengerRecipient.sendMessage{ value: 1 }(
            address(0), 1, new bytes(0), 21_000, ARB_CHAIN_ID, address(mockMessengerRecipient)
        );

        bool success = true;
        uint256 bytesNum = 4;
        string memory bytesStr = "4";
        bytes32 txHash = bytes32(bytesNum);
        bytes memory result = bytes(bytesStr);
        // calling as any account other than the owner should revert
        hevm.prank(address(2));
        hevm.expectRevert("Ownable: caller is not the owner");
        l2MessageVerifier.validateCallback(
            ARB_CHAIN_ID, address(mockMessengerRecipient), nonce, success, txHash, result
        );

        hevm.expectEmit(true, true, true, true);
        emit MockMessengerRecipient.CallbackReceived(nonce, success, txHash);
        l2MessageVerifier.validateCallback(
            ARB_CHAIN_ID, address(mockMessengerRecipient), nonce, success, txHash, result
        );
    }
}
