// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;


interface IWETH {
    function approve(address, uint) external returns (bool);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}