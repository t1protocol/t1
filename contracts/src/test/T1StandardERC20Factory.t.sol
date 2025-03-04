// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { T1StandardERC20 } from "../libraries/token/T1StandardERC20.sol";
import { T1StandardERC20Factory } from "../libraries/token/T1StandardERC20Factory.sol";

contract T1StandardERC20FactoryTest is DSTestPlus {
    T1StandardERC20 private impl;
    T1StandardERC20Factory private factory;

    function setUp() public {
        impl = new T1StandardERC20();
        factory = new T1StandardERC20Factory(address(impl));
    }

    function testDeployL2Token(address _gateway, address _l1Token) external {
        // call by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        factory.deployL2Token(_gateway, _l1Token);
        hevm.stopPrank();

        // call by owner, should succeed
        address computed = factory.computeL2TokenAddress(_gateway, _l1Token);
        address deployed = factory.deployL2Token(_gateway, _l1Token);
        assertEq(computed, deployed);
    }
}
