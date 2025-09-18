// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

/**
 * @dev An abstract contract that extends `Script`.
 *      - Provides helper functions to log addresses to both console and .env
 *      - Provides helper functions to write commented headers/footers to .env
 */
abstract contract DeploymentUtils is Script {
    bool internal immutable IS_MAINNET = vm.envOr("IS_MAINNET", false);
    uint256 private deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
    /**
     * @dev Logs a header in .env to indicate the start of lines produced by {scriptName}.
     *      e.g.: # BEGIN output from ...
     */

    function logStart(string memory scriptName) internal {
        vm.writeLine(".env", "# ---------------------------------------------------------");
        vm.writeLine(".env", string(abi.encodePacked("# BEGIN output from ", scriptName)));
        vm.writeLine(".env", "# ---------------------------------------------------------");
    }

    /**
     * @dev Logs a footer in .env to indicate the end of lines produced by {scriptName}.
     *      e.g.: # END output from ...
     */
    function logEnd(string memory scriptName) internal {
        vm.writeLine(".env", "# ---------------------------------------------------------");
        vm.writeLine(".env", string(abi.encodePacked("# END output from ", scriptName)));
        vm.writeLine(".env", "# ---------------------------------------------------------");
    }

    /**
     * @dev Logs an address both to the console and appends it to .env
     *      e.g.: L1_PROXY_ADMIN_ADDR=0x...
     */
    function logAddress(string memory name, address addr) internal {
        string memory line = string(abi.encodePacked(name, "=", vm.toString(addr)));
        console.log(line);
        vm.writeLine(".env", line);
    }

    function selectMainnetOrSepoliaFork(string memory fork) internal {
        if (IS_MAINNET) {
            string memory answer = vm.prompt("!!! You are about to interact with MAINNET. Be paranoid !!! Type 'yes' to confirm mainnet interaction: ");
            require(keccak256(bytes(answer)) == keccak256(bytes("yes")), "Mainnet interaction aborted by user");
        }

        vm.createSelectFork(IS_MAINNET ? vm.rpcUrl(fork) : vm.rpcUrl(string.concat(fork, "_sepolia")));
    }

    function startBroadcastWithDeployerKeyIfItExists() internal {
        if (deployerPrivateKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerPrivateKey);
        }
    }
}
