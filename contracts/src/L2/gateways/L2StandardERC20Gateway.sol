// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { IL2ERC20Gateway, L2ERC20Gateway } from "./L2ERC20Gateway.sol";
import { IL2T1Messenger } from "../IL2T1Messenger.sol";
import { IL1ERC20Gateway } from "../../L1/gateways/IL1ERC20Gateway.sol";
import { IT1ERC20Upgradeable } from "../../libraries/token/IT1ERC20Upgradeable.sol";
import { T1StandardERC20 } from "../../libraries/token/T1StandardERC20.sol";
import { IT1StandardERC20Factory } from "../../libraries/token/IT1StandardERC20Factory.sol";
import { T1GatewayBase } from "../../libraries/gateway/T1GatewayBase.sol";
import { T1Constants } from "../../libraries/constants/T1Constants.sol";

/// @title L2StandardERC20Gateway
/// @notice The `L2StandardERC20Gateway` is used to withdraw standard ERC20 tokens on layer 2 and
/// finalize deposit the tokens from layer 1.
/// @dev The withdrawn ERC20 tokens will be burned directly. On finalizing deposit, the corresponding
/// token will be minted and transferred to the recipient. Any ERC20 that requires non-standard functionality
/// should use a separate gateway.
contract L2StandardERC20Gateway is L2ERC20Gateway {
    using AddressUpgradeable for address;

    /**
     *
     * Constants *
     *
     */

    /// @notice The address of T1StandardERC20Factory.
    address public immutable tokenFactory;

    /**
     *
     * Variables *
     *
     */

    /// @notice Mapping from l2 token address to l1 token address.
    mapping(address => address) private tokenMapping;

    /**
     *
     * Constructor *
     *
     */

    /// @notice Constructor for `L2StandardERC20Gateway` implementation contract.
    ///
    /// @param _counterpart The address of `L1StandardERC20Gateway` contract in L1.
    /// @param _router The address of `L2GatewayRouter` contract in L2.
    /// @param _messenger The address of `L2T1Messenger` contract in L2.
    /// @param _tokenFactory The address of `T1StandardERC20Factory` contract in L2.
    constructor(
        address _counterpart,
        address _router,
        address _messenger,
        address _tokenFactory
    )
        T1GatewayBase(_counterpart, _router, _messenger)
    {
        if (_router == address(0) || _tokenFactory == address(0)) revert ErrorZeroAddress();

        _disableInitializers();

        tokenFactory = _tokenFactory;
    }

    /// @notice Initialize the storage of L2StandardERC20Gateway.
    function initialize() external initializer {
        T1GatewayBase._initialize();
    }

    /**
     *
     * Public View Functions *
     *
     */

    /// @inheritdoc IL2ERC20Gateway
    function getL1ERC20Address(address _l2Token) external view override returns (address) {
        return tokenMapping[_l2Token];
    }

    /// @inheritdoc IL2ERC20Gateway
    function getL2ERC20Address(address _l1Token) public view override returns (address) {
        return IT1StandardERC20Factory(tokenFactory).computeL2TokenAddress(address(this), _l1Token);
    }

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @inheritdoc IL2ERC20Gateway
    function finalizeDepositERC20(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    )
        external
        payable
        override
        // onlyCallByCounterpart
        // TODO this should not be L1 Messenger address. it should be the Postman identity address
        nonReentrant
    {
        require(msg.value == 0, "nonzero msg.value");
        require(_l1Token != address(0), "token address cannot be 0");

        {
            // avoid stack too deep
            address _expectedL2Token =
                IT1StandardERC20Factory(tokenFactory).computeL2TokenAddress(address(this), _l1Token);
            require(_l2Token == _expectedL2Token, "l2 token mismatch");
        }

        bool _hasMetadata;
        (_hasMetadata, _data) = abi.decode(_data, (bool, bytes));

        bytes memory _deployData;
        bytes memory _callData;

        if (_hasMetadata) {
            (_callData, _deployData) = abi.decode(_data, (bytes, bytes));
        } else {
            require(tokenMapping[_l2Token] == _l1Token, "token mapping mismatch");
            _callData = _data;
        }

        if (!_l2Token.isContract()) {
            // first deposit, update mapping
            tokenMapping[_l2Token] = _l1Token;

            _deployL2Token(_deployData, _l1Token);
        }

        IT1ERC20Upgradeable(_l2Token).mint(_to, _amount);

        _doCallback(_to, _callData);

        emit FinalizeDepositERC20(_l1Token, _l2Token, _from, _to, _amount, _callData);
    }

    /**
     *
     * Internal Functions *
     *
     */

    /// @inheritdoc L2ERC20Gateway
    function _withdraw(
        address _token,
        address _to,
        uint256 _amount,
        bytes memory _data,
        uint256 _gasLimit
    )
        internal
        virtual
        override
        nonReentrant
    {
        require(_amount > 0, "withdraw zero amount");

        // 1. Extract real sender if this call is from L2GatewayRouter.
        address _from = _msgSender();
        if (router == _from) {
            (_from, _data) = abi.decode(_data, (address, bytes));
        }

        address _l1Token = tokenMapping[_token];
        require(_l1Token != address(0), "no corresponding l1 token");

        // 2. Burn token.
        IT1ERC20Upgradeable(_token).burn(_from, _amount);

        // 3. Generate message passed to L1StandardERC20Gateway.
        bytes memory _message =
            abi.encodeCall(IL1ERC20Gateway.finalizeWithdrawERC20, (_l1Token, _token, _from, _to, _amount, _data));

        // 4. send message to L2T1Messenger
        IL2T1Messenger(messenger).sendMessage{ value: msg.value }(
            counterpart, 0, _message, _gasLimit, T1Constants.L1_CHAIN_ID
        );

        emit WithdrawERC20(_l1Token, _token, _from, _to, _amount, _data);
    }

    function _deployL2Token(bytes memory _deployData, address _l1Token) internal {
        address _l2Token = IT1StandardERC20Factory(tokenFactory).deployL2Token(address(this), _l1Token);
        (string memory _symbol, string memory _name, uint8 _decimals) = abi.decode(_deployData, (string, string, uint8));
        T1StandardERC20(_l2Token).initialize(_name, _symbol, _decimals, address(this), _l1Token);
    }
}
