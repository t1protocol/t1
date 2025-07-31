// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

interface IYieldProtocol {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function totalAssets() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract xYieldVault is ERC4626, Ownable2Step, ReentrancyGuard, Pausable {
    using Math for uint256;

    address public guardian;
    IYieldProtocol public yieldProtocol;

    uint256 public virtualTotalAssets;
    bool public isActiveChain;

    mapping(uint256 => address) public siblingVaults;

    uint256 public minRebalanceGap;
    uint256 public lastRebalanceTime;

    error NotGuardian();
    error ZeroAmount();
    error InvalidChain();
    error RebalanceTooFrequent();
    error WithdrawOnInactiveChain();
    error DepositOnInactiveChain();
    error NotImplemented();

    event SharePriceUpdated(uint256 newVirtualTotalAssets);
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
    ) ERC4626(underlying) ERC20(_name, _symbol) {
        guardian = _guardian;
        yieldProtocol = IYieldProtocol(_yieldProtocol);
        isActiveChain = true;
        minRebalanceGap = 1 hours;

        if (_yieldProtocol != address(0)) {
            underlying.approve(_yieldProtocol, type(uint256).max);
        }

        _transferOwnership(msg.sender);
    }

    function deposit(uint256 assets, address receiver) public virtual override nonReentrant whenNotPaused returns (uint256) {
        if (assets == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();

        uint256 shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override nonReentrant whenNotPaused returns (uint256) {
        if (shares == 0) revert ZeroAmount();
        if (!isActiveChain) revert DepositOnInactiveChain();

        uint256 assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
        if (assets == 0) revert ZeroAmount();
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        uint256 shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
        if (shares == 0) revert ZeroAmount();
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        uint256 assets = previewRedeem(shares);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    function remoteDeposit(uint256 assets, uint64 chainId) external nonReentrant whenNotPaused returns (uint256) {
        // TODO: Implement cross-chain deposit coordination
        revert NotImplemented();
    }

    function remoteWithdraw(uint256 assets, address receiver, uint64 chainId) external nonReentrant returns (uint256) {
        // TODO: Implement cross-chain withdraw coordination
        revert NotImplemented();
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        IERC20(asset()).transferFrom(caller, address(this), assets);

        // Should only be called on active chains now
        if (!isActiveChain) revert DepositOnInactiveChain();

        yieldProtocol.deposit(assets, address(this));
        virtualTotalAssets += assets;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Should only be called on active chains where assets exist
        if (!isActiveChain) revert WithdrawOnInactiveChain();

        yieldProtocol.withdraw(assets, address(this), address(this));
        virtualTotalAssets -= assets;
        _burn(owner, shares);
        IERC20(asset()).transfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function totalAssets() public view virtual override returns (uint256) {
        if (isActiveChain && address(yieldProtocol) != address(0)) {
            return yieldProtocol.totalAssets();
        }
        return virtualTotalAssets;
    }

    function updateSharePrice(uint256 newVirtualTotalAssets) external onlyGuardian {
        virtualTotalAssets = newVirtualTotalAssets;
        emit SharePriceUpdated(newVirtualTotalAssets);
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
        yieldProtocol = IYieldProtocol(newYieldProtocol);
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