// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { ClonesUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import { IERC20MetadataUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";

import { IL2ERC20Gateway } from "../../L2/gateways/IL2ERC20Gateway.sol";
import { IL1T1Messenger } from "../IL1T1Messenger.sol";
import { IL1ERC20Gateway } from "./IL1ERC20Gateway.sol";
import { IL1StandardERC20Gateway } from "./IL1StandardERC20Gateway.sol";
import { IL1GatewayRouter } from "../../L1/gateways/IL1GatewayRouter.sol";

import { T1Constants } from "../../libraries/constants/T1Constants.sol";
import { T1GatewayBase } from "../../libraries/gateway/T1GatewayBase.sol";
import { L1ERC20Gateway } from "./L1ERC20Gateway.sol";

/// @title L1StandardERC20Gateway
/// @notice The `L1StandardERC20Gateway` is used to deposit standard ERC20 tokens on layer 1 and
/// finalize withdraw the tokens from layer 2.
/// @dev The deposited ERC20 tokens are held in this gateway. On finalizing withdraw, the corresponding
/// token will be transfer to the recipient directly. Any ERC20 that requires non-standard functionality
/// should use a separate gateway.
/// @dev It includes a function to grant allowances to the `L1GatewayRouter` to swap against reserves.
contract L1StandardERC20Gateway is L1ERC20Gateway, IL1StandardERC20Gateway {
    /**
     *
     * Constants *
     *
     */

    /// @notice The address of T1StandardERC20 implementation in L2.
    address public immutable l2TokenImplementation;

    /// @notice The address of T1StandardERC20Factory contract in L2.
    address public immutable l2TokenFactory;

    /**
     *
     * Variables *
     *
     */

    /// @notice Mapping from l1 token address to l2 token address.
    /// @dev This is not necessary, since we can compute the address directly. But, we use this mapping
    /// to keep track on whether we have deployed the token in L2 using the L2T1StandardERC20Factory and
    /// pass deploy data on first call to the token.
    mapping(address => address) private tokenMapping;

    /**
     *
     * Constructor *
     *
     */

    /// @notice Constructor for `L1StandardERC20Gateway` implementation contract.
    ///
    /// @param _counterpart The address of `L2StandardERC20Gateway` contract in L2.
    /// @param _router The address of `L1GatewayRouter` contract in L1.
    /// @param _messenger The address of `L1T1Messenger` contract in L1.
    /// @param _l2TokenImplementation The address of `T1StandardERC20` implementation in L2.
    /// @param _l2TokenFactory The address of `T1StandardERC20Factory` contract in L2.
    constructor(
        address _counterpart,
        address _router,
        address _messenger,
        address _l2TokenImplementation,
        address _l2TokenFactory
    )
        T1GatewayBase(_counterpart, _router, _messenger)
    {
        if (_router == address(0) || _l2TokenImplementation == address(0) || _l2TokenFactory == address(0)) {
            revert ErrorZeroAddress();
        }

        _disableInitializers();

        l2TokenImplementation = _l2TokenImplementation;
        l2TokenFactory = _l2TokenFactory;
    }

    /// @notice Initialize the storage of L1StandardERC20Gateway.
    function initialize() external initializer {
        T1GatewayBase._initialize();
    }

    /**
     *
     * Public View Functions *
     *
     */

    /// @inheritdoc IL1ERC20Gateway
    function getL2ERC20Address(address _l1Token) public view override returns (address) {
        // In StandardERC20Gateway, all corresponding l2 tokens are depoyed by Create2 with salt,
        // we can calculate the l2 address directly.
        bytes32 _salt = keccak256(abi.encodePacked(counterpart, keccak256(abi.encodePacked(_l1Token))));

        return ClonesUpgradeable.predictDeterministicAddress(l2TokenImplementation, _salt, l2TokenFactory);
    }

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @inheritdoc IL1StandardERC20Gateway
    function allowRouterToTransfer(address token, uint160 amount, uint48 expiration) external {
        require(token != address(0), "Invalid token address");
        require(expiration > block.timestamp, "Expiration must be in the future");

        address permit2 = IL1GatewayRouter(router).permit2();

        // Give permissions to Permit2 if the current ones aren't enough
        if (IERC20MetadataUpgradeable(token).allowance(address(this), permit2) < amount) {
            IERC20MetadataUpgradeable(token).approve(permit2, type(uint160).max);
        }

        // Call the Permit2 `approve` method to grant allowance to the router
        IAllowanceTransfer(permit2).approve(token, T1GatewayBase.router, amount, expiration);
    }

    /**
     *
     * Internal Functions *
     *
     */

    /// @inheritdoc L1ERC20Gateway
    function _beforeFinalizeWithdrawERC20(
        address _l1Token,
        address _l2Token,
        address,
        address,
        uint256,
        bytes calldata
    )
        internal
        virtual
        override
    {
        require(msg.value == 0, "nonzero msg.value");
        require(_l2Token != address(0), "token address cannot be 0");
        require(getL2ERC20Address(_l1Token) == _l2Token, "l2 token mismatch");

        // update `tokenMapping` on first withdraw
        address _storedL2Token = tokenMapping[_l1Token];
        if (_storedL2Token == address(0)) {
            tokenMapping[_l1Token] = _l2Token;
        } else {
            require(_storedL2Token == _l2Token, "l2 token mismatch");
        }
    }

    /// @inheritdoc L1ERC20Gateway
    function _beforeDropMessage(address, address, uint256) internal virtual override {
        require(msg.value == 0, "nonzero msg.value");
    }

    /// @inheritdoc L1ERC20Gateway
    function _deposit(
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
        require(_amount > 0, "deposit zero amount");

        // 1. Transfer token into this contract.
        address _from;
        (_from, _amount, _data) = _transferERC20In(_token, _amount, _data);

        // 2. Generate message passed to L2StandardERC20Gateway.
        address _l2Token = tokenMapping[_token];
        bytes memory _l2Data;
        if (_l2Token == address(0)) {
            // @note we won't update `tokenMapping` here but update the `tokenMapping` on
            // first successful withdraw. This will prevent user to set arbitrary token
            // metadata by setting a very small `_gasLimit` on the first tx.
            _l2Token = getL2ERC20Address(_token);

            // passing symbol/name/decimal in order to deploy in L2.
            string memory _symbol = IERC20MetadataUpgradeable(_token).symbol();
            string memory _name = IERC20MetadataUpgradeable(_token).name();
            uint8 _decimals = IERC20MetadataUpgradeable(_token).decimals();
            _l2Data = abi.encode(true, abi.encode(_data, abi.encode(_symbol, _name, _decimals)));
        } else {
            _l2Data = abi.encode(false, _data);
        }
        bytes memory _message =
            abi.encodeCall(IL2ERC20Gateway.finalizeDepositERC20, (_token, _l2Token, _from, _to, _amount, _l2Data));

        // 3. Send message to L1T1Messenger.
        IL1T1Messenger(messenger).sendMessage{ value: msg.value }(
            counterpart, 0, _message, _gasLimit, T1Constants.T1_DEVNET_CHAIN_ID, _from
        );

        emit DepositERC20(_token, _l2Token, _from, _to, _amount, _data);
    }
}
