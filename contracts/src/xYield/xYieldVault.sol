// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

// TODO: replace with actual Euler interface
interface IYieldProtocol {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function totalAssets() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract xYieldVault is ERC4626, Ownable2Step, ReentrancyGuard, Pausable {
    using Math for uint256;

    address public guardian;
    IYieldProtocol public yieldProtocol;

    uint256 public virtualTotalAssets;
    uint256 public virtualTotalSupply;
    bool public isActiveChain;

    mapping(uint256 => address) public siblingVaults;

    uint256 public minRebalanceGap;
    uint256 public lastRebalanceTime;

    event DepositRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

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
        yieldProtocol = IYieldProtocol(_yieldProtocol);
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

    // function remoteWithdraw(uint256 assets, address receiver, uint64 chainId) external nonReentrant returns (uint256)
    // {
    //     // TODO: Implement cross-chain withdraw coordination
    //     revert NotImplemented();
    // }

    function updateTotals(
        uint256 totalSupply_,
        address[] calldata _recipients,
        uint256[] calldata _amounts
    )
        external
        onlyGuardian
    {
        // update total share token supply
        // TODO - update incrementally like virtualTotalAssets?
        virtualTotalSupply = totalSupply_;
        _updateBalances(_recipients, _amounts);
        emit TotalSupplyUpdated(totalSupply_);
    }

    // TODO - submit proofs for remote deposits
    function _updateBalances(address[] calldata recipients, uint256[] calldata amounts) private {
        if (recipients.length != amounts.length) revert LengthMismatch();
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
            // increment underlying ERC20, e.g. USDC, based on remote deposits
            virtualTotalAssets += amounts[i];
        }
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        IERC20(asset()).transferFrom(caller, address(this), assets);

        yieldProtocol.deposit(assets, address(this));
        // we should just global update only.
        // TODO - does this present potential liveness issues that would otherwise not be present?
        virtualTotalAssets += assets;
        virtualTotalSupply += shares;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _depositFrom(address caller, address receiver, uint256 assets, uint256 shares) internal {
        IERC20(asset()).transferFrom(caller, address(this), assets);

        yieldProtocol.deposit(assets, address(this));
        // DO NOT INCREMENT THIS bc that would mean share price inflation! no new shares but new assets
        // do this only on updateTotals
        // virtualTotalAssets += assets;

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
        // virtualTotalAssets -= assets;
        _burn(owner, shares);
        IERC20(asset()).transfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
        // return virtualTotalSupply > 0 ? virtualTotalSupply : super.totalSupply();
        return virtualTotalSupply;
    }

    function totalAssets() public view virtual override returns (uint256) {
        // TODO - test edge cases where virtual total assets are pending
        if (isActiveChain && address(yieldProtocol) != address(0)) {
            return yieldProtocol.convertToAssets(this.totalSupply());
        }
        return virtualTotalAssets;
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
