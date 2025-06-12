// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { UpgradeT1XChainReaderLogic } from "./UpgradeT1XChainReaderLogic.sol";

/**
 * @title UpgradeT1XChainReader
 * @dev Script to upgrade the T1XChainReader implementation on Sepolia
 *
 * Usage:
 * forge script ./script/upgrade/UpgradeT1XChainReader.s.sol:UpgradeT1XChainReader --rpc-url $T1_L1_RPC --broadcast
 */

// solhint-disable max-states-count
// solhint-disable var-name-mixedcase

contract UpgradeT1XChainReader is UpgradeT1XChainReaderLogic {
    function run() external {
        logStart("UpgradeT1XChainReader.s.sol");
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        _performUpgrade(false);
        logEnd("UpgradeT1XChainReader.s.sol");
    }
}
