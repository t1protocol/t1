// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Whitelist} from "../L2/predeploys/Whitelist.sol";

contract WhitelistTest is Test {
    Whitelist private whitelist;

    function setUp() public {
        whitelist = new Whitelist(address(this));
    }

    function testRenounceOwnership() external {
        // call by non-owner, should revert
        vm.startPrank(address(1));
        vm.expectRevert("caller is not the owner");
        whitelist.renounceOwnership();
        vm.stopPrank();

        // call by owner, should succeed
        assertEq(whitelist.owner(), address(this));
        whitelist.renounceOwnership();
        assertEq(whitelist.owner(), address(0));
    }

    function testTransferOwnership(address _to) external {
        // call by non-owner, should revert
        vm.startPrank(address(1));
        vm.expectRevert("caller is not the owner");
        whitelist.transferOwnership(_to);
        vm.stopPrank();

        // call by owner, should succeed
        if (_to == address(0)) {
            vm.expectRevert("new owner is the zero address");
            whitelist.transferOwnership(_to);
        } else {
            assertEq(whitelist.owner(), address(this));
            whitelist.transferOwnership(_to);
            assertEq(whitelist.owner(), _to);
        }
    }

    function testUpdateWhitelistStatus(address _to) external {
        address[] memory _accounts = new address[](1);
        _accounts[0] = _to;
        // call by non-owner, should revert
        vm.startPrank(address(1));
        vm.expectRevert("caller is not the owner");
        whitelist.updateWhitelistStatus(_accounts, true);
        vm.stopPrank();

        // call by owner, should succeed
        assertEq(whitelist.isSenderAllowed(_to), false);
        whitelist.updateWhitelistStatus(_accounts, true);
        assertEq(whitelist.isSenderAllowed(_to), true);
        whitelist.updateWhitelistStatus(_accounts, false);
        assertEq(whitelist.isSenderAllowed(_to), false);
    }
}
