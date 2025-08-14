// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

contract xYieldVault is ERC4626, Ownable2Step, ReentrancyGuard, Pausable {
    using Math for uint256;

    address public guardian;
    IERC4626 public yieldProtocol;

    uint256 public virtualTotalAssets;
    uint256 public minRebalanceGap;
    uint256 public lastRebalanceTime;
    uint256 public virtualTotalSupply;
    bool public isActiveChain;

    struct BalanceUpdate {
        address recipient;
        uint256 amount;
        bool isMint;
    }

    mapping(uint256 => address) public siblingVaults;

    event DepositRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event WithdrawRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    error NotGuardian();
    error ZeroAmount();
    error InvalidChain();
    error RebalanceTooFrequent();
    error WithdrawOnInactiveChain();
    error DepositOnInactiveChain();
    error NotImplemented();
    error LengthMismatch();

    event TotalSupplyUpdated(uint256 newVirtualTotalSupply);
    event ChainStatusChanged(bool isActive);
    event SiblingVaultSet(uint256 chainId, address vault);
    event Rebalanced(uint256 targetChain, uint256 amount);

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    constructor(
        IERC20 underlying,
        address _guardian,
        string memory _name,
        string memory _symbol,
        address _yieldProtocol
    )
        ERC4626(underlying)
        ERC20(_name, _symbol)
    {
        guardian = _guardian;
        yieldProtocol = IERC4626(_yieldProtocol);
        minRebalanceGap = 1 hours;

        if (_yieldProtocol != address(0)) {
            underlying.approve(_yieldProtocol, type(uint256).max);
        }

        _transferOwnership(msg.sender);
    }

    function deposit(
        uint256 assets,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (assets == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();

        uint256 shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    // called on behalf of a user who has deposited from a remote chain
    function depositFrom(uint256 assets, address receiver) public nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();
        // deposit assets into underlying
        // credit user with virtual deposit
        // render virtual deposits into real deposits when updateTotals is called
        // this means that we will always use virtual deposits to calculate share price
        shares = previewDeposit(assets);
        _depositFrom(msg.sender, receiver, assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (shares == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();

        uint256 assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        if (assets == 0) revert ZeroAmount();
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        uint256 shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        if (shares == 0) revert ZeroAmount();
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        uint256 assets = previewRedeem(shares);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    function withdrawFrom(uint256 assets, address owner, uint64 chainId) external nonReentrant returns (uint256) {
        _withdrawFrom(owner, assets);
    }

    // NOTE - for remote withdrawals we update virtualTotalAssets after withdrawal to prevent share price inflation
    // before
    // global shares is updated
    function _withdrawFrom(address owner, uint256 assets) internal {
        // TODO - deposit into escrow instead of transferring user's underlying to this contract
        uint256 shares = yieldProtocol.withdraw(assets, address(this), address(this));
        emit WithdrawRemote(_msgSender(), owner, assets, shares);
    }

    // used on remote chain to mint share tokens
    // used on highest yield chain to update virtual totals
    // TODO - split out based on active chain
    function updateTotals(uint256 totalSupply_, BalanceUpdate[] calldata balanceUpdates) external onlyGuardian {
        // TODO - update incrementally like virtualTotalAssets using proof of remote supply change
        virtualTotalSupply = totalSupply_;
        _updateBalances(balanceUpdates);
        virtualTotalAssets = this.totalAssets();
        emit TotalSupplyUpdated(totalSupply_);
    }

    function updateVirtualTotalAssets() external onlyGuardian {
        virtualTotalAssets = this.totalAssets();
    }

    // TODO - submit proofs for remote deposits
    function _updateBalances(BalanceUpdate[] calldata balanceUpdates) private {
        for (uint256 i = 0; i < balanceUpdates.length; i++) {
            if (balanceUpdates[i].isMint) {
                _mint(balanceUpdates[i].recipient, balanceUpdates[i].amount);
            } else {
                _burn(balanceUpdates[i].recipient, balanceUpdates[i].amount);
            }
        }
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        virtualTotalAssets += assets;
        virtualTotalSupply += shares;
        _mint(receiver, shares);

        IERC20(asset()).transferFrom(caller, address(this), assets);
        yieldProtocol.deposit(assets, address(this));

        emit Deposit(caller, receiver, assets, shares);
    }

    // NOTE - for remote deposits we update virtualTotalAssets after deposit to prevent share price inflation before
    // global shares is updated
    function _depositFrom(address caller, address receiver, uint256 assets, uint256 shares) internal {
        IERC20(asset()).transferFrom(caller, address(this), assets);
        yieldProtocol.deposit(assets, address(this));

        emit DepositRemote(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        virtual
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Should only be called on active chains where assets exist
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        yieldProtocol.withdraw(assets, address(this), address(this));
        virtualTotalAssets -= assets;
        virtualTotalSupply -= shares;
        _burn(owner, shares);
        IERC20(asset()).transfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
        return virtualTotalSupply;
    }

    function totalAssets() public view virtual override returns (uint256) {
        // TODO - test edge cases where virtual total assets are pending
        return yieldProtocol.convertToAssets(this.totalSupply());
    }

    function setActiveChain(bool _isActive) external onlyGuardian {
        isActiveChain = _isActive;
        emit ChainStatusChanged(_isActive);
    }

    function setSiblingVault(uint256 chainId, address vault) external onlyOwner {
        siblingVaults[chainId] = vault;
        emit SiblingVaultSet(chainId, vault);
    }

    function setGuardian(address newGuardian) external onlyOwner {
        guardian = newGuardian;
    }

    function setYieldProtocol(address newYieldProtocol) external onlyOwner {
        yieldProtocol = IERC4626(newYieldProtocol);
    }

    function setMinRebalanceGap(uint256 newGap) external onlyOwner {
        minRebalanceGap = newGap;
    }

    function rebalance(uint256 targetChain, uint256 amount) external onlyGuardian {
        // TODO: Implement rebalancing
        revert NotImplemented();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
