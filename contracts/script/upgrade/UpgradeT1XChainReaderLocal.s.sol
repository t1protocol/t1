// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {UpgradeT1XChainReaderLogic} from "./UpgradeT1XChainReaderLogic.sol";

/**
 * @title UpgradeT1XChainReaderLocal
 * @dev Script to upgrade the T1XChainReader implementation on local network
 *
 * Usage:
 * forge script ./script/upgrade/UpgradeT1XChainReaderLocal.s.sol:UpgradeT1XChainReaderLocal --rpc-url localhost
 * --broadcast
 */
contract UpgradeT1XChainReaderLocal is UpgradeT1XChainReaderLogic {
    function run() external {
        logStart("UpgradeT1XChainReaderLocal.s.sol");
        _performUpgrade(true);
        logEnd("UpgradeT1XChainReaderLocal.s.sol");
    }
}
