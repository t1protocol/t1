// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @dev An abstract contract that extends `Script`.
 *      - Provides helper functions to log addresses to both console and .env
 *      - Provides helper functions to write commented headers/footers to .env
 */
abstract contract DeploymentUtils is Script {
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
        // 1. Construct the line
        string memory line = string(abi.encodePacked(name, "=", vm.toString(addr)));
        
        // 2. Print to console
        console.log(line);
        
        // 3. Append to .env
        vm.writeLine(".env", line);
    }
}
