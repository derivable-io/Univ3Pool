// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/lib/contracts/libraries/Babylonian.sol";

library UQ48x48 {
    // Square root of UQ48x48
  function sqrt(uint96 x) internal pure returns (uint96) {
    return uint96(Babylonian.sqrt(uint256(x) << 48));
  }
}