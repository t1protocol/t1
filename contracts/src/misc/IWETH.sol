// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

interface IWETH {
    function approve(address, uint256) external returns (bool);
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}
