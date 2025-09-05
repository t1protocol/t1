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

    uint256 public virtualTotalAssets;
    uint256 public virtualTotalSupply;
    bool public isActiveChain;

    enum TxType {
        Deposit,
        Withdraw
    }

    struct BalanceUpdate {
        address recipient;
        uint256 amount;
        TxType txType;
    }

    mapping(uint64 => address) public siblingVaults;

    error NotGuardian();
    error ZeroAmount();
    error InvalidChain();
    error WithdrawOnInactiveChain();
    error DepositOnInactiveChain();
    error NotImplemented();
    error LengthMismatch();
    error InvalidOrderData();

    event DepositRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares, uint64 chainId);
    event WithdrawRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event TotalSupplyUpdated(uint256 newVirtualTotalSupply);
    event ChainStatusChanged(bool isActive);
    event SiblingVaultSet(uint64 chainId, address vault);
    event Rebalanced(uint256 targetChain, uint256 amount);
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
        if (siblingVaults[_chainId] == address(0)) revert InvalidChain();
        // deposit assets into underlying
        // credit user with virtual deposit
        // render virtual deposits into real deposits when updateTotals is called
        // this means that we will always use virtual deposits to calculate share price
        shares = previewDeposit(_amount);
        _depositFrom(msg.sender, _receiver, _amount, shares, _chainId);
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
        if (!isActiveChain) revert WithdrawOnInactiveChain();

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
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        uint256 assets = previewRedeem(_shares);
        _withdraw(msg.sender, _receiver, _owner, assets, _shares);

        return assets;
    }

    function withdrawFrom(
        uint256 assets,
        address owner,
        uint64 chainId
    )
        external
        nonReentrant
        onlyGuardian
        returns (uint256)
    {
        _withdrawFrom(owner, assets);
    }

    // NOTE - for remote withdrawals we update virtualTotalAssets after withdrawal to prevent share price inflation
    // before
    // global shares is updated
    function _withdrawFrom(address owner, uint256 assets) internal {
        // TODO - deposit into escrow instead of transferring user's underlying to this contract
        uint256 shares = yieldProtocol.withdraw(assets, address(this), address(this));
        emit WithdrawRemote(msg.sender, owner, assets, shares);
    }

    // used on remote chain to mint share tokens
    // used on highest yield chain to update virtual totals
    // TODO - split out based on active chain
    function updateTotals(uint256 totalSupply_, BalanceUpdate[] calldata balanceUpdates) external onlyGuardian {
        // TODO - update incrementally like virtualTotalAssets using proof of remote supply change
        virtualTotalSupply = totalSupply_;
        _updateBalances(balanceUpdates);
        virtualTotalAssets = totalAssets();
        emit TotalSupplyUpdated(totalSupply_);
    }

    function updateVirtualTotalAssets() public onlyGuardian {
        virtualTotalAssets = totalAssets();
    }

    // TODO - submit proofs for remote deposits
    function _updateBalances(BalanceUpdate[] calldata balanceUpdates) private {
        for (uint256 i = 0; i < balanceUpdates.length; i++) {
            if (balanceUpdates[i].txType == TxType.Deposit) {
                _mint(balanceUpdates[i].recipient, balanceUpdates[i].amount);
            } else {
                _burn(balanceUpdates[i].recipient, balanceUpdates[i].amount);
            }
        }
    }

    function _deposit(address _caller, address _receiver, uint256 _amount, uint256 _shares) internal virtual override {
        virtualTotalAssets += _amount;
        virtualTotalSupply += _shares;
        _mint(_receiver, _shares);

        IERC20(asset()).safeTransferFrom(_caller, address(this), _amount);
        yieldProtocol.deposit(_amount, address(this));

        emit Deposit(_caller, _receiver, _amount, _shares);
    }

    // NOTE - for remote deposits we update virtualTotalAssets after deposit to prevent share price inflation before
    // global shares is updated
    function _depositFrom(
        address _caller,
        address _receiver,
        uint256 _amount,
        uint256 _shares,
        uint64 _chainId
    )
        internal
    {
        IERC20(asset()).safeTransferFrom(_caller, address(this), _amount);
        yieldProtocol.deposit(_amount, address(this));

        emit DepositRemote(_caller, _receiver, _amount, _shares, _chainId);
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

        yieldProtocol.withdraw(_amount, address(this), address(this));
        virtualTotalAssets -= _amount;
        virtualTotalSupply -= _shares;
        _burn(_owner, _shares);
        IERC20(asset()).safeTransfer(_receiver, _amount);

        emit Withdraw(_caller, _receiver, _owner, _amount, _shares);
    }

    function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
        return virtualTotalSupply;
    }

    function totalAssets() public view virtual override returns (uint256) {
        // TODO - test edge cases where virtual total assets are pending
        return yieldProtocol.convertToAssets(yieldProtocol.balanceOf(address(this)));
    }

    function setActiveChain(bool _isActive) external onlyGuardian {
        isActiveChain = _isActive;
        emit ChainStatusChanged(_isActive);
    }

    function setSiblingVault(uint64 _chainId, address _vault) external onlyOwner {
        siblingVaults[_chainId] = _vault;
        emit SiblingVaultSet(_chainId, _vault);
    }

    function setGuardian(address _newGuardian) external onlyOwner {
        guardian = _newGuardian;
    }

    function setYieldProtocol(address _newYieldProtocol) external onlyOwner {
        yieldProtocol = IERC4626(_newYieldProtocol);
    }

    function rebalance(
        uint32 _targetChain,
        uint256 _amount,
        OnchainCrossChainOrder calldata order
    )
        external
        onlyGuardian
    {
        if (_amount == 0) revert ZeroAmount();
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        address siblingVault = siblingVaults[_targetChain];
        if (siblingVault == address(0)) revert InvalidChain();

        (OrderData memory orderData) = abi.decode(order.orderData, (OrderData));
        if (_targetChain != orderData.destinationDomain) revert InvalidOrderData();
        if (_amount != orderData.amountIn) revert InvalidOrderData();

        isActiveChain = false;

        yieldProtocol.withdraw(_amount, address(this), address(this));
        updateVirtualTotalAssets();
        // open across intent

        emit Rebalanced(_targetChain, _amount);
    }

    /// @notice Wrapper around the settler contract `refund` function to be called after a PoR
    /// has successfully been created with calling `verifyRefund` on settler contact
    /// @dev You ALWAYS need to unse this function instead of regular `refund` on settler contract
    /// as extra logic needs to be ran atomically.
    function undoRebalance(OnchainCrossChainOrder calldata order, bytes calldata proof) external onlyGuardian {
        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = proof;
        // cancel Across intent

        isActiveChain = true;
        virtualTotalAssets = ERC20(asset()).balanceOf(address(this));

        (OrderData memory orderData) = abi.decode(order.orderData, (OrderData));
        yieldProtocol.deposit(orderData.amountIn, address(this));

        emit RebalanceUndone(orderData.destinationDomain, orderData.amountIn);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
