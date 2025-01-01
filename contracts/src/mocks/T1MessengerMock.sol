// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
import "../libraries/constants/T1Constants.sol";

contract T1MessengerMock {
    event SentMessage(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 messageNonce,
        uint256 gasLimit,
        bytes message,
        uint64 indexed destChainId
    );

    uint256 public nonce;

    constructor(){

    }

    function sendMessage(
        address _to,
        uint256 _value,
        bytes memory _message,
        uint256 _gasLimit
    )
    external
    payable
    {
        emit SentMessage(msg.sender, _to, _value, nonce, _gasLimit, _message, T1Constants.T1_DEVNET_CHAIN_ID);
        nonce = nonce + 1;
    }
}
