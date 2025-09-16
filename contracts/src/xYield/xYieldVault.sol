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
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { EIP712 } from "solady/utils/EIP712.sol";

contract xYieldVault is ERC4626, Ownable2Step, ReentrancyGuard, Pausable, EIP712 {
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
        Withdraw
    }

    struct BalanceUpdate {
        address recipient;
        uint256 amount;
        TxType txType;
    }

    struct SiblingVault {
        address vault;
        address underlyingErc20;
    }

    mapping(uint64 => SiblingVault) public siblingVaults;

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
    error InvalidSignature();

    // EIP-712 TypeHash for the deposit intent
    bytes32 public constant DEPOSIT_TYPEHASH = keccak256(
        "DepositIntent(uint64 sourceChainId,address receiver,uint256 amount,uint256 nonce)"
    );

    event DepositRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares, uint64 chainId);
    event WithdrawRemote(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
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
        EIP712()
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
        uint256 _id,
        bytes memory _signature,
        address _outputToken,
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

        // Compose message with signature for verification on target chain
        bytes memory data = abi.encode(uint64(block.chainid), _receiver, _signature);
        bytes memory message = abi.encode(uint8(0), _id, data); // txType = 0 for deposit

        acrossSpokePool.depositV3(
            address(this),
            siblingVaults[_targetChainId].vault,
            asset(),
            _outputToken,
            _amount,
            _outputAmount,
            _targetChainId,
            _exclusiveRelayer,
            _quoteTimestamp,
            _fillDeadline,
            _exclusivityParameter,
            message
        );

        emit DepositRemote(msg.sender, _receiver, _amount, 0, uint64(block.chainid));
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
        nonReentrant
        onlyGuardian
        returns (uint256)
    {
        return _withdrawFrom(
            owner,
            assets,
            chainId,
            outputToken,
            outputAmount,
            exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            exclusivityParameter
        );
    }

    function _withdrawFrom(
        address owner,
        uint256 assets,
        uint64 chainId,
        address outputToken,
        uint256 outputAmount,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter
    )
        internal
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets);
        virtualTotalSupply -= shares;
        yieldProtocol.withdraw(assets, address(this), address(this));

        acrossSpokePool.depositV3(
            address(this),
            owner,
            asset(),
            outputToken,
            assets,
            outputAmount,
            uint256(chainId),
            exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            exclusivityParameter,
            ""
        );

        emit WithdrawRemote(msg.sender, owner, assets, shares);
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
            } else {
                _burn(balanceUpdates[i].recipient, balanceUpdates[i].amount);
            }
        }
    }

    function _deposit(address _caller, address _receiver, uint256 _amount, uint256 _shares) internal virtual override {
        virtualTotalSupply += _shares;
        _mint(_receiver, _shares);

        IERC20(asset()).safeTransferFrom(_caller, address(this), _amount);
        yieldProtocol.deposit(_amount, address(this));

        emit Deposit(_caller, _receiver, _amount, _shares);
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

        virtualTotalSupply -= _shares;
        _burn(_owner, _shares);
        yieldProtocol.withdraw(_amount, address(this), address(this));
        IERC20(asset()).safeTransfer(_receiver, _amount);

        emit Withdraw(_caller, _receiver, _owner, _amount, _shares);
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

    function setSiblingVault(uint64 _chainId, address _vault, address _underlyingErc20) external onlyOwner {
        if (_vault == address(0) || _underlyingErc20 == address(0)) revert NoAddress();

        siblingVaults[_chainId].vault = _vault;
        siblingVaults[_chainId].underlyingErc20 = _underlyingErc20;
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

        bytes memory message = abi.encode(_id);

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
        (uint8 txType, uint256 id, bytes memory data) = abi.decode(message, (uint8, uint256, bytes));
        // 0 = Deposit, 1 = Rebalance
        if (txType == 0) {
            if (!isActiveChain) revert DepositOnInactiveChain();
            // anyone must be able to call this method, so we must check that the recipient authored the intent
            // else an attacker could claim idle funds as their own deposit
            (uint64 chainId, address receiver, bytes memory signature) = abi.decode(data, (uint64, address, bytes));
            if (siblingVaults[chainId].vault == address(0)) revert InvalidChain();

            // Check that the receiver EIP-712 signed this deposit intent
            bytes32 structHash = keccak256(abi.encode(
                DEPOSIT_TYPEHASH,
                chainId,
                receiver,
                amount,
                id  // ID as nonce
            ));

            bytes32 digest = _hashTypedData(structHash);
            if (!SignatureCheckerLib.isValidSignatureNow(receiver, digest, signature)) {
                revert InvalidSignature();
            }

            uint256 shares = previewDeposit(amount);
            virtualTotalSupply += shares;
            yieldProtocol.deposit(amount, address(this));

            emit DepositRemote(msg.sender, receiver, amount, shares, chainId);
        } else if (txType == 1) {
            // Rebalance messages don't need signature verification as they're guardian-initiated
            emit Rebalanced(id, amount);
        } else {
            revert InvalidTxType(txType);
        }
    }

    // Helper function to get the EIP-712 domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    // EIP-712 helper functions required by Solady's EIP712 contract
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        return ("xYieldVault", "1");
    }
}
