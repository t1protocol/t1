// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { V3SpokePoolInterface } from "@across-protocol/contracts/contracts/interfaces/V3SpokePoolInterface.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { OnchainCrossChainOrder } from "../interfaces/IERC7683.sol";
import { OrderData, OrderEncoder } from "../libraries/7683/OrderEncoder.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { T1ERC7683 } from "../7683/T1ERC7683.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

contract xYieldVault is ERC4626, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public guardian;

    IERC4626 public yieldProtocol;
    V3SpokePoolInterface public acrossSpokePool;

    uint256 public virtualTotalSupply;
    bool public isActiveChain;
    uint256 public rebalanceFillTTL = 2 minutes;

    enum TxType {
        Deposit,
        Withdraw,
        Rebalance
    }

    struct BalanceUpdate {
        address recipient;
        uint256 amount;
        TxType txType;
    }

    struct SiblingVault {
        address vault;
        address underlyingErc20;
        // The address of the Across MulticallHandler which calls the depositFrom method
        address multicallHandler;
    }

    struct Call {
        address target;
        bytes callData;
        uint256 value;
    }

    struct Instructions {
        Call[] calls;
        address fallbackRecipient;
    }

    mapping(uint64 chainId => SiblingVault) public siblingVaults;

    error NotGuardian();
    error ZeroAmount();
    error InvalidChain();
    error WithdrawOnInactiveChain();
    error DepositOnInactiveChain();
    error OnlyRemote();
    error NotImplemented();
    error LengthMismatch();
    error InvalidOrderData();
    error NoAddress();
    error InvalidTxType(uint8 txType);
    error InvalidTokenSent();

    event XYieldDepositRemoteInitiated(
        address indexed sender, address indexed owner, uint256 outputAmount, uint64 targetChainId
    );
    event XYieldDeposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint64 sourceChainId,
        bool isRemote
    );
    event XYieldWithdraw(
        address indexed sender,
        address indexed owner,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint64 targetChainId,
        bool isRemote
    );
    event TotalSupplyUpdated(uint256 newVirtualTotalSupply);
    event ChainStatusChanged(bool isActive);
    event SiblingVaultSet(uint64 chainId, address vault);
    event RebalanceInitiated(uint256 indexed id, uint256 targetChain, uint256 amount);
    event Rebalanced(uint256 indexed id, uint256 amount);
    event RebalanceUndone(uint256 targetChain, uint256 amount);

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    constructor(
        IERC20 _underlying,
        address _guardian,
        string memory _name,
        string memory _symbol,
        address _yieldProtocol,
        address _acrossSpokePool
    )
        ERC4626(_underlying)
        ERC20(_name, _symbol)
    {
        guardian = _guardian;
        yieldProtocol = IERC4626(_yieldProtocol);
        acrossSpokePool = V3SpokePoolInterface(_acrossSpokePool);

        if (_yieldProtocol != address(0)) {
            _underlying.approve(_yieldProtocol, type(uint256).max);
        }
        if (_acrossSpokePool != address(0)) {
            _underlying.approve(_acrossSpokePool, type(uint256).max);
        }
        if (_acrossSpokePool != address(0)) {
            _underlying.approve(_acrossSpokePool, type(uint256).max);
        }
    }

    function deposit(uint256 _amount, address _receiver) public virtual override whenNotPaused returns (uint256) {
        if (_amount == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();

        uint256 shares = previewDeposit(_amount);
        _deposit(msg.sender, _receiver, _amount, shares);

        return shares;
    }

    // called on behalf of a user who has deposited from a remote chain
    function depositFrom(
        uint256 _amount,
        address _receiver,
        uint64 _chainId
    )
        external
        whenNotPaused
        returns (uint256 shares)
    {
        if (_amount == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();
        if (siblingVaults[_chainId].vault == address(0)) revert InvalidChain();
        shares = previewDeposit(_amount);
        _depositFrom(msg.sender, _receiver, _amount, shares, _chainId);
    }

    // Initiates a cross-chain deposit to the active vault from a remote chain
    function depositTo(
        uint256 _amount,
        address _receiver,
        uint64 _targetChainId,
        uint256 _outputAmount,
        address _exclusiveRelayer,
        uint32 _quoteTimestamp,
        uint32 _fillDeadline,
        uint32 _exclusivityParameter
    )
        external
        whenNotPaused
        nonReentrant
    {
        if (_amount == 0) revert ZeroAmount();
        if (isActiveChain) revert OnlyRemote();
        if (siblingVaults[_targetChainId].vault == address(0)) revert InvalidChain();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), _amount);

        // Create instructions for multicall handler to:
        // 1. Approve the vault to spend tokens
        // 2. Call depositFrom on target vault
        bytes memory approveCallData =
            abi.encodeCall(IERC20.approve, (siblingVaults[_targetChainId].vault, _outputAmount));

        bytes memory depositCallData =
            abi.encodeCall(this.depositFrom, (_outputAmount, _receiver, uint64(block.chainid)));

        Call[] memory calls = new Call[](2);
        calls[0] = Call({ target: siblingVaults[_targetChainId].underlyingErc20, callData: approveCallData, value: 0 });
        calls[1] = Call({ target: siblingVaults[_targetChainId].vault, callData: depositCallData, value: 0 });

        Instructions memory instructions = Instructions({ calls: calls, fallbackRecipient: _receiver });

        bytes memory message = abi.encode(instructions);

        acrossSpokePool.depositV3(
            address(this),
            siblingVaults[_targetChainId].multicallHandler,
            asset(),
            siblingVaults[_targetChainId].underlyingErc20,
            _amount,
            _outputAmount,
            _targetChainId,
            _exclusiveRelayer,
            _quoteTimestamp,
            _fillDeadline,
            _exclusivityParameter,
            message
        );

        emit XYieldDepositRemoteInitiated(msg.sender, _receiver, _outputAmount, _targetChainId);
    }

    function mint(uint256 _shares, address _receiver) public virtual override whenNotPaused returns (uint256) {
        if (_shares == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();

        uint256 assets = previewMint(_shares);
        _deposit(msg.sender, _receiver, assets, _shares);

        return assets;
    }

    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    )
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        if (_amount == 0) revert ZeroAmount();

        uint256 shares = previewWithdraw(_amount);
        _withdraw(msg.sender, _receiver, _owner, _amount, shares);

        return shares;
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    )
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        if (_shares == 0) revert ZeroAmount();

        uint256 assets = previewRedeem(_shares);
        _withdraw(msg.sender, _receiver, _owner, assets, _shares);

        return assets;
    }

    function redeemFrom(
        uint256 shares,
        address owner,
        uint64 chainId,
        uint256 outputAmount,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter
    )
        external
        nonReentrant
        onlyGuardian
        returns (uint256 assets)
    {
        assets = previewRedeem(shares);
        _withdrawFrom(
            owner, shares, assets, chainId, outputAmount, exclusiveRelayer, quoteTimestamp, fillDeadline, exclusivityParameter
        );
    }

    function withdrawFrom(
        uint256 assets,
        address owner,
        uint64 chainId,
        uint256 outputAmount,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter
    )
        external
        nonReentrant
        onlyGuardian
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets);
        _withdrawFrom(
            owner, shares, assets, chainId, outputAmount, exclusiveRelayer, quoteTimestamp, fillDeadline, exclusivityParameter
        );
    }

    function _withdrawFrom(
        address owner,
        uint256 shares,
        uint256 assets,
        uint64 chainId,
        uint256 outputAmount,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter
    )
        internal
    {
        virtualTotalSupply -= shares;
        yieldProtocol.withdraw(assets, address(this), address(this));

        acrossSpokePool.depositV3(
            address(this),
            owner,
            asset(),
            siblingVaults[chainId].underlyingErc20,
            assets,
            outputAmount,
            uint256(chainId),
            exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            exclusivityParameter,
            ""
        );

        emit XYieldWithdraw(msg.sender, owner, owner, outputAmount, shares, uint64(chainId), true);
    }

    // used on remote chain to mint share tokens
    // used on highest yield chain to update virtual totals
    // TODO - split out based on active chain
    function updateTotals(uint256 totalSupply_, BalanceUpdate[] calldata balanceUpdates) external onlyGuardian {
        if (isActiveChain) revert OnlyRemote();
        virtualTotalSupply = totalSupply_;
        _updateBalances(balanceUpdates);
        emit TotalSupplyUpdated(totalSupply_);
    }

    function finalizeRebalance() external onlyGuardian {
        _depositIdleAssets();
        _setActiveChain(true);
    }

    function _depositIdleAssets() internal {
        uint256 idleBalance = IERC20(asset()).balanceOf(address(this));
        if (idleBalance == 0) revert ZeroAmount();
        yieldProtocol.deposit(idleBalance, address(this));
    }

    // TODO - submit proofs for remote deposits
    function _updateBalances(BalanceUpdate[] calldata balanceUpdates) private {
        for (uint256 i = 0; i < balanceUpdates.length; i++) {
            if (balanceUpdates[i].txType == TxType.Deposit) {
                _mint(balanceUpdates[i].recipient, balanceUpdates[i].amount);
            } else if (balanceUpdates[i].txType == TxType.Withdraw) {
                _burn(balanceUpdates[i].recipient, balanceUpdates[i].amount);
            } else {
                revert InvalidTxType(uint8(balanceUpdates[i].txType));
            }
        }
    }

    function _deposit(address _caller, address _receiver, uint256 _amount, uint256 _shares) internal virtual override {
        virtualTotalSupply += _shares;
        _mint(_receiver, _shares);

        IERC20(asset()).safeTransferFrom(_caller, address(this), _amount);
        yieldProtocol.deposit(_amount, address(this));

        emit XYieldDeposit(_caller, _receiver, _amount, _shares, uint64(block.chainid), false);
    }

    function _depositFrom(
        address _caller,
        address _receiver,
        uint256 _amount,
        uint256 _shares,
        uint64 _chainId
    )
        internal
    {
        virtualTotalSupply += _shares;
        IERC20(asset()).safeTransferFrom(_caller, address(this), _amount);
        yieldProtocol.deposit(_amount, address(this));

        emit XYieldDeposit(_caller, _receiver, _amount, _shares, _chainId, true);
    }

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _amount,
        uint256 _shares
    )
        internal
        virtual
        override
    {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }

        // Should only be called on active chains where assets exist
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        virtualTotalSupply -= _shares;
        _burn(_owner, _shares);
        yieldProtocol.withdraw(_amount, address(this), address(this));
        IERC20(asset()).safeTransfer(_receiver, _amount);

        emit XYieldWithdraw(_caller, _receiver, _owner, _amount, _shares, uint64(block.chainid), false);
    }

    function _setActiveChain(bool _isActive) internal {
        isActiveChain = _isActive;
        emit ChainStatusChanged(_isActive);
    }

    function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
        return virtualTotalSupply;
    }

    function totalAssets() public view virtual override returns (uint256) {
        return yieldProtocol.convertToAssets(yieldProtocol.balanceOf(address(this)));
    }

    function setActiveChain(bool _isActive) external onlyGuardian {
        _setActiveChain(_isActive);
    }

    function setSiblingVault(
        uint64 _chainId,
        address _vault,
        address _underlyingErc20,
        address _multicallHandler
    )
        external
        onlyOwner
    {
        if (_vault == address(0) || _underlyingErc20 == address(0) || _multicallHandler == address(0)) {
            revert NoAddress();
        }

        siblingVaults[_chainId].vault = _vault;
        siblingVaults[_chainId].underlyingErc20 = _underlyingErc20;
        siblingVaults[_chainId].multicallHandler = _multicallHandler;
        emit SiblingVaultSet(_chainId, _vault);
    }

    function setGuardian(address _newGuardian) external onlyOwner {
        guardian = _newGuardian;
    }

    function setYieldProtocol(address _newYieldProtocol) external onlyOwner {
        IERC20(asset()).approve(address(yieldProtocol), 0);
        yieldProtocol = IERC4626(_newYieldProtocol);
        IERC20(asset()).approve(_newYieldProtocol, type(uint256).max);
    }

    function setAcrossSpokePool(address _newAcrossSpokePool) external onlyOwner {
        IERC20(asset()).approve(address(acrossSpokePool), 0);
        acrossSpokePool = V3SpokePoolInterface(_newAcrossSpokePool);
        IERC20(asset()).approve(_newAcrossSpokePool, type(uint256).max);
    }

    function setRebalanceFillTTL(uint256 newTTL) external onlyOwner {
        rebalanceFillTTL = newTTL;
    }

    function rebalance(
        uint256 _id,
        uint32 _targetChain,
        uint256 _amountIn,
        uint256 _amountOut,
        uint32 _acrossApiQuoteTimestamp
    )
        external
        onlyGuardian
    {
        if (_amountIn == 0) revert ZeroAmount();
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        SiblingVault memory siblingVault = siblingVaults[_targetChain];
        if (siblingVault.vault == address(0)) revert InvalidChain();

        _setActiveChain(false);

        yieldProtocol.withdraw(_amountIn, address(this), address(this));

        bytes memory message = abi.encode(uint8(TxType.Rebalance), _id);

        acrossSpokePool.depositV3(
            address(this),
            siblingVault.vault,
            asset(),
            siblingVault.underlyingErc20,
            _amountIn,
            _amountOut,
            _targetChain,
            address(0),
            _acrossApiQuoteTimestamp,
            uint32(block.timestamp + rebalanceFillTTL),
            0,
            message
        );

        emit RebalanceInitiated(_id, _targetChain, _amountIn);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message) external {
        if (tokenSent != asset()) revert InvalidTokenSent();
        if (amount == 0) revert ZeroAmount();

        (uint8 txType, uint256 id) = abi.decode(message, (uint8, uint256));

        if (txType == uint8(TxType.Rebalance)) {
            emit Rebalanced(id, amount);
        } else {
            revert InvalidTxType(txType);
        }
    }
}
