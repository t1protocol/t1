// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IT1ERC20Extension } from "./IT1ERC20Extension.sol";

// The recommended ERC20 implementation for bridge token.
// deployed in L2 when original token is on L1
// deployed in L1 when original token is on L2
interface IT1ERC20 is IERC20, IERC20Permit, IT1ERC20Extension { }
