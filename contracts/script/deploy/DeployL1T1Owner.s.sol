// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { T1Owner } from "../../src/misc/T1Owner.sol";

// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract DeployL1T1Owner is Script {
    string NETWORK = vm.envString("NETWORK");

    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    address T1_MULTISIG_ADDR = vm.envAddress("L1_T1_MULTISIG_ADDR");

    address SECURITY_COUNCIL_ADDR = vm.envAddress("L1_SECURITY_COUNCIL_ADDR");

    address L1_PROPOSAL_EXECUTOR_ADDR = vm.envAddress("L1_PROPOSAL_EXECUTOR_ADDR");

    function run() external {
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        deployT1Owner();

        if (keccak256(abi.encodePacked(NETWORK)) == keccak256(abi.encodePacked("sepolia"))) {
            // for sepolia
            deployTimelockController("1D", 1 minutes);
            deployTimelockController("7D", 7 minutes);
            deployTimelockController("14D", 14 minutes);
        } else if (keccak256(abi.encodePacked(NETWORK)) == keccak256(abi.encodePacked("mainnet"))) {
            // for mainnet
            deployTimelockController("1D", 1 days);
            deployTimelockController("7D", 7 days);
            deployTimelockController("14D", 14 days);
        }

        vm.stopBroadcast();
    }

    function deployT1Owner() internal {
        T1Owner owner = new T1Owner();

        logAddress("L1_T1_OWNER_ADDR", address(owner));
    }

    function deployTimelockController(string memory label, uint256 delay) internal {
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);

        proposers[0] = T1_MULTISIG_ADDR;
        executors[0] = L1_PROPOSAL_EXECUTOR_ADDR;

        TimelockController timelock = new TimelockController(delay, proposers, executors, SECURITY_COUNCIL_ADDR);

        logAddress(string(abi.encodePacked("L1_", label, "_TIMELOCK_ADDR")), address(timelock));
    }

    function logAddress(string memory name, address addr) internal pure {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
