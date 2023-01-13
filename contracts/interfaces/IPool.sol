// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface IPool {
    function COLLATERAL_TOKEN() external view returns (address);
	function swap(
        uint idIn,
        uint idOut,
        address recipient
    ) external returns (uint amountOut);
    // TODO: flashSwap
}