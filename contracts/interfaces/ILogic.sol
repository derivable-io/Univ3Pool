// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILogic {
    function COLLATERAL_TOKEN() external view returns (address);
    function N_TOKENS() external view returns (uint);
    function PRICE_ORACLE() external view returns (address);
    function BASE_TOKEN_0() external view returns (bool);
    function POOL() external view returns (address);
    function deleverage(uint224 start, uint224 end) external returns (uint224 mid);
    function swap(uint idIn, uint idOut) external returns (uint amountOut, bool needVerifying);
    function verify() external;
    // function getAmountOut(address tokenIn, address tokenOut, uint amountIn) external view returns (uint amountOut);
}