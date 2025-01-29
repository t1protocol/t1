// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

import { IL1ETHGateway } from "./IL1ETHGateway.sol";
import { IL1ERC20Gateway } from "./IL1ERC20Gateway.sol";
import { IL1GatewayRouter } from "./IL1GatewayRouter.sol";

/// @title L1GatewayRouter
/// @notice The `L1GatewayRouter` is the main entry for depositing Ether and ERC20 tokens.
/// All deposited tokens are routed to corresponding gateways.
/// @dev One can also use this contract to query L1/L2 token address mapping.
/// It also includes a new functionality for swapping ERC20 tokens using `Permit2`.
contract L1GatewayRouter is OwnableUpgradeable, IL1GatewayRouter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     *
     * Variables *>
     *
     */

    /// @notice The address of L1ETHGateway.
    address public ethGateway;

    /// @notice The addess of default ERC20 gateway, normally the L1StandardERC20Gateway contract.
    address public defaultERC20Gateway;

    /// @notice Mapping from ERC20 token address to corresponding L1ERC20Gateway.
    // solhint-disable-next-line var-name-mixedcase
    mapping(address => address) public ERC20Gateway;

    /// @notice The address of gateway in current execution context.
    address public gatewayInContext;

    /// @notice The Permit2 `SignatureTransfer` contract.
    address public signatureTransfer;

    /// @notice The Permit2 `AllowanceTransfer` contract.
    address public allowanceTransfer;

    /**
     *
     * Function Modifiers *
     *
     */
    modifier onlyNotInContext() {
        require(gatewayInContext == address(0), "Only not in context");
        _;
    }

    modifier onlyInContext() {
        require(_msgSender() == gatewayInContext, "Only in deposit context");
        _;
    }

    /**
     *
     * Constructor *
     *
     */
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the storage of L1GatewayRouter.
    /// @param _ethGateway The address of L1ETHGateway contract.
    /// @param _defaultERC20Gateway The address of default ERC20 Gateway contract.
    /// @param _signatureTransfer The address of the `SignatureTransfer` contract.
    /// @param _allowanceTransfer The address of the `AllowanceTransfer` contract.
    function initialize(
        address _ethGateway,
        address _defaultERC20Gateway,
        address _allowanceTransfer,
        address _signatureTransfer
    )
        external
        initializer
    {
        OwnableUpgradeable.__Ownable_init();

        // it can be zero during initialization
        if (_defaultERC20Gateway != address(0)) {
            defaultERC20Gateway = _defaultERC20Gateway;
            emit SetDefaultERC20Gateway(address(0), _defaultERC20Gateway);
        }

        // it can be zero during initialization
        if (_ethGateway != address(0)) {
            ethGateway = _ethGateway;
            emit SetETHGateway(address(0), _ethGateway);
        }

        // it can be zero during initialization
        if (_signatureTransfer != address(0)) {
            signatureTransfer = _signatureTransfer;
            emit SetSignatureTransfer(address(0), _signatureTransfer);
        }

        // it can be zero during initialization
        if (_allowanceTransfer != address(0)) {
            allowanceTransfer = _allowanceTransfer;
            emit SetAllowanceTransfer(address(0), _allowanceTransfer);
        }
    }

    /**
     *
     * Public View Functions *
     *
     */

    /// @inheritdoc IL1ERC20Gateway
    function getL2ERC20Address(address _l1Address) external view override returns (address) {
        address _gateway = getERC20Gateway(_l1Address);
        if (_gateway == address(0)) {
            return address(0);
        }

        return IL1ERC20Gateway(_gateway).getL2ERC20Address(_l1Address);
    }

    /// @inheritdoc IL1GatewayRouter
    function getERC20Gateway(address _token) public view returns (address) {
        address _gateway = ERC20Gateway[_token];
        if (_gateway == address(0)) {
            _gateway = defaultERC20Gateway;
        }
        return _gateway;
    }

    /// @inheritdoc IL1GatewayRouter
    function calculateOutputAmount(
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 providedRate
    )
        public
        view
        returns (uint256 outputAmount)
    {
        uint8 inputDecimals = IERC20MetadataUpgradeable(inputToken).decimals();
        uint8 outputDecimals = IERC20MetadataUpgradeable(outputToken).decimals();

        // Normalize the amount to `outputToken`'s decimals
        if (inputDecimals > outputDecimals) {
            outputAmount = (inputAmount * providedRate * (10 ** outputDecimals)) / (10 ** inputDecimals) / 1e18;
        } else {
            outputAmount = (inputAmount * providedRate * (10 ** (outputDecimals - inputDecimals))) / 1e18;
        }

        require(outputAmount > 0, "Output amount must be > than 0");

        // Validate the defaultERC20Gateway has enough reserves of the output token
        uint256 outputTokenBalance = IERC20Upgradeable(outputToken).balanceOf(defaultERC20Gateway);
        require(outputAmount <= outputTokenBalance, "Insufficient reserves");
    }

    /**
     *
     * Public Mutating Functions *
     *
     */

    /// @inheritdoc IL1GatewayRouter
    /// @dev All the gateways should have reentrancy guard to prevent potential attack though this function.
    function requestERC20(address _sender, address _token, uint256 _amount) external onlyInContext returns (uint256) {
        address _caller = _msgSender();
        uint256 _balance = IERC20Upgradeable(_token).balanceOf(_caller);
        IERC20Upgradeable(_token).safeTransferFrom(_sender, _caller, _amount);
        _amount = IERC20Upgradeable(_token).balanceOf(_caller) - _balance;
        return _amount;
    }

    /// @inheritdoc IL1GatewayRouter
    function swapERC20(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        address outputToken,
        uint256 providedRate,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata permitSignature
    )
        external
        returns (uint256 outputAmount)
    {
        address inputToken = permit.permitted.token;
        uint256 inputAmount = permit.permitted.amount;
        uint256 nonce = permit.nonce;
        uint256 deadline = permit.deadline;
        address outputTokenMemory = outputToken;
        uint256 providedRateMemory = providedRate;
        address ownerMemory = owner;
        bytes32 witnessMemory = witness;
        string calldata witnessTypeStringMemory = witnessTypeString;
        bytes calldata permitSignatureMemory = permitSignature;

        require(inputToken != address(0), "Invalid input token address");
        require(outputTokenMemory != address(0), "Invalid output token address");
        require(inputToken != outputTokenMemory, "Cannot swap the same token");
        require(inputAmount > 0, "Input amount must be > than 0");
        require(providedRateMemory > 0, "Rate must be > than 0");
        require(ownerMemory != address(0), "Invalid owner address");

        // TODO decode and check witness?

        uint256 outputAmount_ = calculateOutputAmount(inputToken, inputAmount, outputTokenMemory, providedRateMemory);

        // Use Permit2 to validate and transfer input tokens from `owner` to the defaultERC20Gateway
        _permitWitnessTransfer(
            inputToken,
            inputAmount,
            nonce,
            deadline,
            ownerMemory,
            witnessMemory,
            witnessTypeStringMemory,
            permitSignatureMemory
        );

        // Use AllowanceTransfer to transfer the output tokens from the defaultERC20Gateway to the `owner` address
        IAllowanceTransfer(allowanceTransfer).transferFrom(
            defaultERC20Gateway, ownerMemory, uint160(outputAmount_), outputTokenMemory
        );

        emit Swap(ownerMemory, inputToken, outputTokenMemory, inputAmount, outputAmount_, providedRateMemory);

        return outputAmount_;
    }

    /**
     *
     * Public Mutating Functions from L1ERC20Gateway *
     *
     */

    /// @inheritdoc IL1ERC20Gateway
    function depositERC20(address _token, uint256 _amount, uint256 _gasLimit) external payable override {
        depositERC20AndCall(_token, _msgSender(), _amount, new bytes(0), _gasLimit);
    }

    /// @inheritdoc IL1ERC20Gateway
    function depositERC20(address _token, address _to, uint256 _amount, uint256 _gasLimit) external payable override {
        depositERC20AndCall(_token, _to, _amount, new bytes(0), _gasLimit);
    }

    /// @inheritdoc IL1ERC20Gateway
    function depositERC20AndCall(
        address _token,
        address _to,
        uint256 _amount,
        bytes memory _data,
        uint256 _gasLimit
    )
        public
        payable
        override
        onlyNotInContext
    {
        address _gateway = getERC20Gateway(_token);
        require(_gateway != address(0), "no gateway available");

        // enter deposit context
        gatewayInContext = _gateway;

        // encode msg.sender with _data
        bytes memory _routerData = abi.encode(_msgSender(), _data);

        IL1ERC20Gateway(_gateway).depositERC20AndCall{ value: msg.value }(_token, _to, _amount, _routerData, _gasLimit);

        // leave deposit context
        gatewayInContext = address(0);
    }

    /// @inheritdoc IL1ERC20Gateway
    function finalizeWithdrawERC20(
        address,
        address,
        address,
        address,
        uint256,
        bytes calldata
    )
        external
        payable
        virtual
        override
    {
        revert("should never be called");
    }

    /**
     *
     * Public Mutating Functions from L1ETHGateway *
     *
     */

    /// @inheritdoc IL1ETHGateway
    function depositETH(uint256 _amount, uint256 _gasLimit) external payable override {
        depositETHAndCall(_msgSender(), _amount, new bytes(0), _gasLimit);
    }

    /// @inheritdoc IL1ETHGateway
    function depositETH(address _to, uint256 _amount, uint256 _gasLimit) external payable override {
        depositETHAndCall(_to, _amount, new bytes(0), _gasLimit);
    }

    /// @inheritdoc IL1ETHGateway
    function depositETHAndCall(
        address _to,
        uint256 _amount,
        bytes memory _data,
        uint256 _gasLimit
    )
        public
        payable
        override
        onlyNotInContext
    {
        address _gateway = ethGateway;
        require(_gateway != address(0), "eth gateway available");

        // encode msg.sender with _data
        bytes memory _routerData = abi.encode(_msgSender(), _data);

        IL1ETHGateway(_gateway).depositETHAndCall{ value: msg.value }(_to, _amount, _routerData, _gasLimit);
    }

    /// @inheritdoc IL1ETHGateway
    function finalizeWithdrawETH(address, address, uint256, bytes calldata) external payable virtual override {
        revert("should never be called");
    }

    /**
     *
     * Restricted Functions *
     *
     */

    /// @inheritdoc IL1GatewayRouter
    function setETHGateway(address _newEthGateway) external onlyOwner {
        address _oldETHGateway = ethGateway;
        ethGateway = _newEthGateway;

        emit SetETHGateway(_oldETHGateway, _newEthGateway);
    }

    /// @inheritdoc IL1GatewayRouter
    function setDefaultERC20Gateway(address _newDefaultERC20Gateway) external onlyOwner {
        address _oldDefaultERC20Gateway = defaultERC20Gateway;
        defaultERC20Gateway = _newDefaultERC20Gateway;

        emit SetDefaultERC20Gateway(_oldDefaultERC20Gateway, _newDefaultERC20Gateway);
    }

    /// @inheritdoc IL1GatewayRouter
    function setERC20Gateway(address[] memory _tokens, address[] memory _gateways) external onlyOwner {
        require(_tokens.length == _gateways.length, "length mismatch");

        for (uint256 i = 0; i < _tokens.length; i++) {
            address _oldGateway = ERC20Gateway[_tokens[i]];
            ERC20Gateway[_tokens[i]] = _gateways[i];

            emit SetERC20Gateway(_tokens[i], _oldGateway, _gateways[i]);
        }
    }

    /// @inheritdoc IL1GatewayRouter
    function setSignatureTransfer(address _newSignatureTransfer) external onlyOwner {
        address _oldSignatureTransfer = signatureTransfer;
        signatureTransfer = _newSignatureTransfer;

        emit SetSignatureTransfer(_oldSignatureTransfer, _newSignatureTransfer);
    }

    /// @inheritdoc IL1GatewayRouter
    function setAllowanceTransfer(address _newAllowanceTransfer) external onlyOwner {
        address _oldAllowanceTransfer = allowanceTransfer;
        allowanceTransfer = _newAllowanceTransfer;

        emit SetAllowanceTransfer(_oldAllowanceTransfer, _newAllowanceTransfer);
    }

    /**
     *
     * Internal Functions *
     *
     */
    function _permitWitnessTransfer(
        address inputToken,
        uint256 inputAmount,
        uint256 nonce,
        uint256 deadline,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata permitSignature
    )
        internal
    {
        ISignatureTransfer(signatureTransfer).permitWitnessTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({ token: inputToken, amount: inputAmount }),
                nonce: nonce,
                deadline: deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({ to: defaultERC20Gateway, requestedAmount: inputAmount }),
            owner,
            witness,
            witnessTypeString,
            permitSignature
        );
    }
}
