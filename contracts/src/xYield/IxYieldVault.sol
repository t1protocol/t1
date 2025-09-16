// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IxYieldVault {
    type TxType is uint8;

    struct BalanceUpdate {
        address recipient;
        uint256 amount;
        TxType txType;
    }

    error DepositOnInactiveChain();
    error InvalidChain();
    error InvalidOrderData();
    error InvalidSignature();
    error InvalidTokenSent();
    error InvalidTxType(uint8 txType);
    error LengthMismatch();
    error NoAddress();
    error NotGuardian();
    error NotImplemented();
    error OnlyRemote();
    error WithdrawOnInactiveChain();
    error ZeroAmount();

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event ChainStatusChanged(bool isActive);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event DepositRemote(
        address indexed sender, address indexed owner, uint256 assets, uint256 shares, uint64 sourceChainId
    );
    event DepositRemoteInitiated(address indexed sender, address indexed owner, uint256 assets, uint64 targetChainId);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event RebalanceInitiated(uint256 indexed id, uint256 targetChain, uint256 amount);
    event RebalanceUndone(uint256 targetChain, uint256 amount);
    event Rebalanced(uint256 indexed id, uint256 amount);
    event SiblingVaultSet(uint64 chainId, address vault);
    event TotalSupplyUpdated(uint256 newVirtualTotalSupply);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Unpaused(address account);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event WithdrawRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    function DEPOSIT_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function acceptOwnership() external;
    function acrossSpokePool() external view returns (address);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function deposit(uint256 _amount, address _receiver) external returns (uint256);
    function depositTo(
        uint256 _amount,
        address _receiver,
        uint64 _targetChainId,
        uint256 _id,
        bytes memory _signature,
        address _outputToken,
        uint256 _outputAmount,
        address _exclusiveRelayer,
        uint32 _quoteTimestamp,
        uint32 _fillDeadline,
        uint32 _exclusivityParameter
    )
        external;
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function finalizeRebalance() external;
    function guardian() external view returns (address);
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message) external;
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function isActiveChain() external view returns (bool);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function mint(uint256 _shares, address _receiver) external returns (uint256);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function pendingOwner() external view returns (address);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function rebalance(
        uint256 _id,
        uint32 _targetChain,
        uint256 _amountIn,
        uint256 _amountOut,
        uint32 _acrossApiQuoteTimestamp
    )
        external;
    function rebalanceFillTTL() external view returns (uint256);
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256);
    function renounceOwnership() external;
    function setAcrossSpokePool(address _newAcrossSpokePool) external;
    function setActiveChain(bool _isActive) external;
    function setGuardian(address _newGuardian) external;
    function setRebalanceFillTTL(uint256 newTTL) external;
    function setSiblingVault(uint64 _chainId, address _vault, address _underlyingErc20) external;
    function setYieldProtocol(address _newYieldProtocol) external;
    function siblingVaults(uint64) external view returns (address vault, address underlyingErc20);
    function symbol() external view returns (string memory);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transferOwnership(address newOwner) external;
    function unpause() external;
    function updateTotals(uint256 totalSupply_, BalanceUpdate[] memory balanceUpdates) external;
    function virtualTotalSupply() external view returns (uint256);
    function withdraw(uint256 _amount, address _receiver, address _owner) external returns (uint256);
    function withdrawFrom(
        uint256 assets,
        address owner,
        uint64 chainId,
        address outputToken,
        uint256 outputAmount,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter
    )
        external
        returns (uint256);
    function yieldProtocol() external view returns (address);
}
