// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/UQ48x48.sol";
import "./libraries/TickMath.sol";

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Pool {
  using UQ48x48 for uint96;
  using TickMath for uint160;

  address public immutable COLLATERAL_TOKEN;
  address public immutable TOKEN0;
  address public immutable TOKEN1;
  //UQ48x48
  uint96 public immutable PRICE_RATE_X48;

  int24 private _currentUpperTick;
  int24 private _currentLowerTick;
  uint128 private _liquidity;

  constructor(address collateralToken, uint96 priceRateRange) {
    COLLATERAL_TOKEN = collateralToken;
    (TOKEN0, TOKEN1) = _getTokensInColateral();
    PRICE_RATE_X48 = priceRateRange;
  }

  function _decompose() internal returns (uint amount0Recieved, uint amount1Recieved) {
    if (_liquidity > 0) 
      (amount0Recieved, amount1Recieved) = IUniswapV3Pool(COLLATERAL_TOKEN).burn(
        _currentLowerTick, 
        _currentUpperTick, 
        _liquidity
      );
  }

  function _safeTransferFrom(address token, address sender, address to, uint amount) internal {
    if (sender == address(this)) {
        return TransferHelper.safeTransfer(token, to, amount);
    }
    return TransferHelper.safeTransferFrom(token, sender, to, amount);
  }

  function _getTokensInColateral() internal virtual returns (address token0, address token1) {
    token1 = IUniswapV3Pool(COLLATERAL_TOKEN).token1();
    token0 = IUniswapV3Pool(COLLATERAL_TOKEN).token0();
  }

  function _calSqrtHighPrice(uint160 sqrtPriceX96, uint96 sqrtRateX48) internal pure returns (uint160) {
    return uint160((uint256(sqrtPriceX96) * uint256(sqrtRateX48)) >> 48);
  }

  function _calSqrtLowPrice(uint160 sqrtPriceX96, uint96 sqrtRateX48) internal pure returns (uint160) {
    return uint160((uint256(sqrtPriceX96) << 48) / uint256(sqrtRateX48));
  }

  //TODO: Condition?
  function recompose(uint baseAmountDesired, uint quoteAmountDesired) external {
    //TODO: Decompose
    _decompose();

    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(COLLATERAL_TOKEN).slot0();
    uint96 sqrtRateX48 = PRICE_RATE_X48.sqrt();
    uint160 sqrtHiPriceX96 = _calSqrtHighPrice(sqrtPriceX96, sqrtRateX48);
    uint160 sqrtLoPriceX96 = _calSqrtLowPrice(sqrtPriceX96, sqrtRateX48);

    int24 upperTick = sqrtHiPriceX96.getTickAtSqrtRatio();
    int24 lowerTick = sqrtLoPriceX96.getTickAtSqrtRatio();

    //TODO: calculate liquidity base on baseAmountDesired and quoteAmountDesired
    uint128 liquidity = 0;
    IUniswapV3Pool(COLLATERAL_TOKEN).mint(
      address(this), 
      lowerTick,
      upperTick, 
      _liquidity, 
      bytes("")
    );

    // Update state
    _liquidity = liquidity;
    _currentLowerTick = lowerTick;
    _currentUpperTick = upperTick;
  }

  // TODO: remove this in production
  function exhaust(address token) external {
    TransferHelper.safeTransfer(token, msg.sender, IERC20(token).balanceOf(address(this)));
  }
}
