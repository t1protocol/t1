// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { t1_7683Message } from "../libraries/7683/t1_7683Message.sol";
import { BasicSwap7683 } from "@7683/BasicSwap7683.sol";

import { L1T1Messenger } from "../L1/L1T1Messenger.sol";
import { IL1T1Messenger } from "../L1/IL1T1Messenger.sol";

/**
 * @title L1_t1_7683
 * @author t1
 * @notice This contract builds on top of BasicSwap7683 as a messaging layer using t1.
 * @dev It integrates with the t1 protocol for cross-chain communication.
 */
contract L1_t1_7683 is BasicSwap7683, OwnableUpgradeable {
    // ============ Libraries ============

    // ============ Constants ============

    uint32 internal constant DEFAULT_GAS_LIMIT = 1_000_000;

    uint32 public immutable localDomain;

    IL1T1Messenger public immutable messenger;

    // ============ Public Storage ============

    // ============ Upgrade Gap ============
    /// @dev Reserved storage slots for upgradeability.
    uint256[47] private __GAP;

    // ============ Events ============

    // ============ Errors ============

    // ============ Modifiers ============

    // ============ Constructor ============
    /**
     * @notice Initializes the t17683 contract with the specified Mailbox and PERMIT2 address.
     * @param _messenger The address of the _messenger contract.
     * @param _permit2 The address of the permit2 contract.
     * @param localDomain_ The local domain.
     */
    constructor(address _messenger, address _permit2, uint32 localDomain_) BasicSwap7683(_permit2) {
        messenger = IL1T1Messenger(_messenger);
        localDomain = localDomain_;
    }

    // ============ Initializers ============

    /**
     * @notice Initializes the contract
     * @param _customHook used by the Router to set the hook to override with
     * @param _interchainSecurityModule The address of the local ISM contract
     * @param _owner The address with owner privileges
     */
     // TODO - add counterpart
    function initialize(address _customHook, address _interchainSecurityModule, address _owner) external initializer {
        // _MailboxClient_initialize(_customHook, _interchainSecurityModule, _owner);
    }

    // ============ Internal Functions ============

    /**
     * @notice Dispatches a settlement message to the specified domain.
     * @dev Encodes the settle message using t1_7683Message and dispatches it via the GasRouter.
     * @param _originDomain The domain to which the settlement message is sent.
     * @param _orderIds The IDs of the orders to settle.
     * @param _ordersFillerData The filler data for the orders.
     */
    function _dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    ) internal override {
        bytes memory message = abi.encode(true, _orderIds, _ordersFillerData);
        messenger.sendMessage(
            // TODO - where are we sending this?
            address(0),
            0,
            message,
            DEFAULT_GAS_LIMIT
        );
    }

    /**
     * @notice Dispatches a refund message to the specified domain.
     * @dev Encodes the refund message using t1_7683Message and dispatches it via the GasRouter.
     * @param _originDomain The domain to which the refund message is sent.
     * @param _orderIds The IDs of the orders to refund.
     */
    function _dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) internal override {
        // TODO - replace with call to L2T1Messenger.sendMessage
    }

    /**
     * @notice Handles incoming messages.
     * @dev Decodes the message and processes settlement or refund operations accordingly.
     * _originDomain The domain from which the message originates (unused in this implementation).
     * _sender The address of the sender on the origin domain (unused in this implementation).
     * @param _message The encoded message received via t1.
     */
     // TODO - virtual override
    function _handle(uint32, bytes32, bytes calldata _message) internal {
        (bool _settle, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
            t1_7683Message.decode(_message);

        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_settle) {
                _handleSettleOrder(_orderIds[i], abi.decode(_ordersFillerData[i], (bytes32)));
            } else {
                _handleRefundOrder(_orderIds[i]);
            }
        }
    }

    /**
     * @notice Handles an incoming message
     * @param _origin The origin domain
     * @param _sender The sender address
     * @param _message The message
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
        // TODO - onlyMessenger
    ) external payable {
        _handle(_origin, _sender, _message);
    }

    /**
     * @notice Retrieves the local domain identifier.
     * @dev This function overrides the `_localDomain` function from the parent contract.
     * @return The local domain ID.
     */
    function _localDomain() internal view override returns (uint32) {
        return localDomain;
    }
}
