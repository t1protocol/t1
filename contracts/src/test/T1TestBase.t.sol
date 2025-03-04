// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { EmptyContract } from "../misc/EmptyContract.sol";

abstract contract T1TestBase is DSTestPlus {
    ProxyAdmin internal admin;

    EmptyContract private placeholder;

    function __T1TestBase_setUp() internal {
        admin = new ProxyAdmin();
        placeholder = new EmptyContract();
    }

    function _deployProxy(address _logic) internal returns (address) {
        if (_logic == address(0)) _logic = address(placeholder);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(_logic, address(admin), new bytes(0));
        return address(proxy);
    }
}
