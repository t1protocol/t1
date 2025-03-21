// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { IL2ETHGateway } from "../../L2/gateways/IL2ETHGateway.sol";
import { IL1T1Messenger } from "../IL1T1Messenger.sol";
import { IL1ETHGateway } from "./IL1ETHGateway.sol";

import { IMessageDropCallback } from "../../libraries/callbacks/IMessageDropCallback.sol";
import { T1GatewayBase } from "../../libraries/gateway/T1GatewayBase.sol";
import { T1Constants } from "../../libraries/constants/T1Constants.sol";

// solhint-disable avoid-low-level-calls

/// @title L1ETHGateway
/// @notice The `L1ETHGateway` is used to deposit ETH on layer 1 and
/// finalize withdraw ETH from layer 2.
/// @dev The deposited ETH tokens are held in this gateway. On finalizing withdraw, the corresponding
/// ETH will be transfer to the recipient directly.
contract L1ETHGateway is T1GatewayBase, IL1ETHGateway, IMessageDropCallback {
    /**
     *
     * Constructor *
     *
     */

    /// @notice Constructor for `L1ETHGateway` implementation contract.
    ///
    /// @param _counterpart The address of `L2ETHGateway` contract in L2.
    /// @param _router The address of `L1GatewayRouter` contract in L1.
    /// @param _messenger The address of `L1T1Messenger` contract in L1.
    constructor(
        address _counterpart,
        address _router,
        address _messenger
    )
        T1GatewayBase(_counterpart, _router, _messenger)
    {
        if (_router == address(0)) revert ErrorZeroAddress();

        _disableInitializers();
    }

    /// @notice Initialize the storage of L1ETHGateway.
    function initialize() external initializer {
        T1GatewayBase._initialize();
    }

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @inheritdoc IL1ETHGateway
    function depositETH(uint256 _amount, uint256 _gasLimit) external payable override {
        _deposit(_msgSender(), _amount, new bytes(0), _gasLimit);
    }

    /// @inheritdoc IL1ETHGateway
    function depositETH(address _to, uint256 _amount, uint256 _gasLimit) external payable override {
        _deposit(_to, _amount, new bytes(0), _gasLimit);
    }

    /// @inheritdoc IL1ETHGateway
    function depositETHAndCall(
        address _to,
        uint256 _amount,
        bytes calldata _data,
        uint256 _gasLimit
    )
        external
        payable
        override
    {
        _deposit(_to, _amount, _data, _gasLimit);
    }

    /// @inheritdoc IL1ETHGateway
    function finalizeWithdrawETH(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    )
        external
        payable
        override
        //        onlyCallByCounterpart // TODO this should not be L1 Messenger address. it should be the Postman
        // identity address
        nonReentrant
    {
        require(msg.value == _amount, "msg.value mismatch");

        // @note can possible trigger reentrant call to messenger,
        // but it seems not a big problem.
        (bool _success,) = _to.call{ value: _amount }("");
        require(_success, "ETH transfer failed");

        _doCallback(_to, _data);

        emit FinalizeWithdrawETH(_from, _to, _amount, _data);
    }

    /// @inheritdoc IMessageDropCallback
    function onDropMessage(bytes calldata _message)
        external
        payable
        virtual
        //    onlyInDropContext // TODO this should not be L1 Messenger address. it should be the Postman identity
        // address
        nonReentrant
    {
        // _message should start with 0x232e8748  =>  finalizeDepositETH(address,address,uint256,bytes)
        require(bytes4(_message[0:4]) == IL2ETHGateway.finalizeDepositETH.selector, "invalid selector");

        // decode (receiver, amount)
        (address _receiver,, uint256 _amount,) = abi.decode(_message[4:], (address, address, uint256, bytes));

        require(_amount == msg.value, "msg.value mismatch");

        (bool _success,) = _receiver.call{ value: _amount }("");
        require(_success, "ETH transfer failed");

        emit RefundETH(_receiver, _amount);
    }

    /**
     *
     * Internal Functions *
     *
     */

    /// @dev The internal ETH deposit implementation.
    /// @param _to The address of recipient's account on L2.
    /// @param _amount The amount of ETH to be deposited.
    /// @param _data Optional data to forward to recipient's account.
    /// @param _gasLimit Gas limit required to complete the deposit on L2.
    function _deposit(
        address _to,
        uint256 _amount,
        bytes memory _data,
        uint256 _gasLimit
    )
        internal
        virtual
        nonReentrant
    {
        require(_amount > 0, "deposit zero eth");

        // 1. Extract real sender if this call is from L1GatewayRouter.
        address _from = _msgSender();

        if (router == _from) {
            (_from, _data) = abi.decode(_data, (address, bytes));
        }

        // @note no rate limit here, since ETH is limited in messenger

        // 2. Generate message passed to L1T1Messenger.
        bytes memory _message = abi.encodeCall(IL2ETHGateway.finalizeDepositETH, (_from, _to, _amount, _data));

        IL1T1Messenger(messenger).sendMessage{ value: msg.value }(
            counterpart, _amount, _message, _gasLimit, T1Constants.T1_DEVNET_CHAIN_ID, _from
        );

        emit DepositETH(_from, _to, _amount, _data);
    }
}
