// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

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
import { T1Constants } from "../../libraries/constants/T1Constants.sol";

/// @title L1GatewayRouter
/// @notice The `L1GatewayRouter` is the main entry for depositing Ether and ERC20 tokens.
/// All deposited tokens are routed to corresponding gateways.
/// @dev One can also use this contract to query L1/L2 token address mapping.
/// It also includes a new functionality for swapping ERC20 tokens using `Permit2`.
contract L1GatewayRouter is OwnableUpgradeable, IL1GatewayRouter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     *
     * Variables *
     *
     */

    /// @notice The address of L1ETHGateway.
    address public ethGateway;

    /// @notice The address of default ERC20 gateway, normally the L1StandardERC20Gateway contract.
    address public defaultERC20Gateway;

    /// @notice Mapping from ERC20 token address to corresponding L1ERC20Gateway.
    // solhint-disable-next-line var-name-mixedcase
    mapping(address erc20TokenAddress => address L1ERC20Gateway) public ERC20Gateway;

    /// @notice The address of gateway in current execution context.
    address public gatewayInContext;

    /// @notice The Permit2 contract.
    address public permit2;

    /// @notice The address of the market maker.
    address public marketMaker;

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
     * @dev Throws if called by any account other than the market maker.
     */
    modifier onlyMM() {
        require(_msgSender() == marketMaker, "Only the market maker");
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
    /// @param _permit2 The address of the Permit2 contract.
    function initialize(address _ethGateway, address _defaultERC20Gateway, address _permit2) external initializer {
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
        if (_permit2 != address(0)) {
            permit2 = _permit2;
            emit SetPermit2(address(0), _permit2);
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
    function swapERC20(SwapParams calldata params) external onlyMM {
        _validateSwap(params);

        address outputGateway = getERC20Gateway(params.witness.outputTokenAddress);
        // Validate if there are enough reserves of the output token
        require(
            params.witness.outputTokenAmount
                <= IERC20MetadataUpgradeable(params.witness.outputTokenAddress).balanceOf(outputGateway),
            "Insufficient reserves"
        );

        // Encoded witness data to be included when checking the user signature
        bytes32 witness = keccak256(abi.encode(T1Constants.WITNESS_TYPEHASH, params.witness));

        // Use Permit2 to validate and transfer input tokens from `owner` to the input gateway
        ISignatureTransfer(permit2).permitWitnessTransferFrom(
            params.permit,
            ISignatureTransfer.SignatureTransferDetails({
                to: getERC20Gateway(params.permit.permitted.token),
                requestedAmount: params.permit.permitted.amount
            }),
            params.owner,
            witness,
            T1Constants.WITNESS_TYPE_STRING,
            params.sig
        );

        // Use AllowanceTransfer to transfer the output tokens from the output gateway to the `owner` address
        IAllowanceTransfer(permit2).transferFrom(
            outputGateway, params.owner, uint160(params.witness.outputTokenAmount), params.witness.outputTokenAddress
        );

        emit Swap(
            params.owner,
            params.permit.permitted.token,
            params.witness.outputTokenAddress,
            params.permit.permitted.amount,
            params.witness.outputTokenAmount
        );
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

    /// @inheritdoc IL1ERC20Gateway
    function allowRouterToTransfer(address, uint160, uint48) external virtual override {
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
    function setPermit2(address _newPermit2) external onlyOwner {
        address _oldPermit2 = permit2;
        permit2 = _newPermit2;

        emit SetPermit2(_oldPermit2, _newPermit2);
    }

    /// @inheritdoc IL1GatewayRouter
    function setMM(address _newMM) external onlyOwner {
        address _oldMM = marketMaker;
        marketMaker = _newMM;

        emit SetMM(_oldMM, _newMM);
    }

    /**
     *
     * Internal Functions *
     *
     */
    function _validateSwap(SwapParams calldata params) internal pure {
        require(params.permit.permitted.token != address(0), "Invalid input token address");
        require(params.witness.outputTokenAddress != address(0), "Invalid output token address");
        require(params.permit.permitted.token != params.witness.outputTokenAddress, "Cannot swap the same token");
        require(params.permit.permitted.amount > 0, "Input amount must be > than 0");
        require(params.witness.outputTokenAmount > 0, "Output amount must be > than 0");
        require(params.owner != address(0), "Invalid owner address");
    }
}
