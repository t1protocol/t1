// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IT1Gateway } from "./IT1Gateway.sol";
import { IT1Messenger } from "../IT1Messenger.sol";
import { IT1GatewayCallback } from "../callbacks/IT1GatewayCallback.sol";
import { T1Constants } from "../constants/T1Constants.sol";

/// @title T1GatewayBase
/// @notice The `T1GatewayBase` is a base contract for gateway contracts used in both in L1 and L2.
abstract contract T1GatewayBase is ReentrancyGuardUpgradeable, OwnableUpgradeable, IT1Gateway {
    /**
     *
     * Constants *
     *
     */

    /// @inheritdoc IT1Gateway
    address public immutable override counterpart;

    /// @inheritdoc IT1Gateway
    address public immutable override router;

    /// @inheritdoc IT1Gateway
    address public immutable override messenger;

    /**
     *
     * Variables *
     *
     */

    /// @dev The storage slots for future usage.
    uint256[46] private __gap;

    /**
     *
     * Function Modifiers *
     *
     */
    modifier onlyCallByCounterpart() {
        // check caller is messenger
        if (_msgSender() != messenger) {
            revert ErrorCallerIsNotMessenger();
        }

        // check cross domain caller is counterpart gateway
        if (counterpart != IT1Messenger(messenger).xDomainMessageSender()) {
            revert ErrorCallerIsNotCounterpartGateway();
        }
        _;
    }

    modifier onlyInDropContext() {
        // check caller is messenger
        if (_msgSender() != messenger) {
            revert ErrorCallerIsNotMessenger();
        }

        // check we are dropping message in T1Messenger.
        if (T1Constants.DROP_XDOMAIN_MESSAGE_SENDER != IT1Messenger(messenger).xDomainMessageSender()) {
            revert ErrorNotInDropMessageContext();
        }
        _;
    }

    /**
     *
     * Constructor *
     *
     */
    constructor(address _counterpart, address _router, address _messenger) {
        if (_counterpart == address(0) || _messenger == address(0)) {
            revert ErrorZeroAddress();
        }

        counterpart = _counterpart;
        router = _router;
        messenger = _messenger;
    }

    function _initialize(address, address, address) internal {
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init();
    }

    /**
     *
     * Internal Functions *
     *
     */

    /// @dev Internal function to forward calldata to target contract.
    /// @param _to The address of contract to call.
    /// @param _data The calldata passed to the contract.
    function _doCallback(address _to, bytes memory _data) internal {
        if (_data.length > 0 && _to.code.length > 0) {
            IT1GatewayCallback(_to).onT1GatewayCallback(_data);
        }
    }
}
