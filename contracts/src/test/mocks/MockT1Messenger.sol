// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IT1Messenger } from "../../libraries/IT1Messenger.sol";

// solhint-disable no-empty-blocks

contract MockT1Messenger is IT1Messenger {
    address public override xDomainMessageSender;

    /**
     *
     * Public Mutating Functions *
     *
     */
    function setXDomainMessageSender(address _xDomainMessageSender) external {
        xDomainMessageSender = _xDomainMessageSender;
    }

    function callTarget(address to, bytes calldata data) external payable {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(to).call{ value: msg.value }(data);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }

    function sendMessage(address _to, uint256 _value, bytes memory _message, uint256 _gasLimit) external payable { }

    function sendMessage(
        address _to,
        uint256 _value,
        bytes memory _message,
        uint256 _gasLimit,
        address _refundAddress
    )
        external
        payable
    { }
}
