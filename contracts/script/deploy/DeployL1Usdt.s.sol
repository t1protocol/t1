// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";

import { DeploymentUtils } from "../lib/DeploymentUtils.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// solhint-disable var-name-mixedcase

contract Usdt is ERC20 {
    constructor(uint256 initialSupply) ERC20("USDT", "USDT") {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Returns the number of decimals used to get user representation.
     * @dev Override the default OpenZeppelin ERC20 decimals() to match USDT standard (6 decimals).
     * @return uint8 The number of decimals (6).
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract DeployL1Usdt is Script, DeploymentUtils {
    function run() external {
        logStart("DeployL1Usdt");

        uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);
        Usdt usdt = new Usdt(1_000_000 * 1e6);
        vm.stopBroadcast();

        logAddress("L1_USDT_ADDR", address(usdt));

        logEnd("DeployL1Usdt");
    }
}
