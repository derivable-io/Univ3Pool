// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";


contract Pool is IUniswapV3MintCallback {
  using TickMath for uint160;

  bool public immutable BASE_TOKEN_0;

  address public immutable COLLATERAL_TOKEN;
  address public immutable TOKEN_BASE;
  address public immutable TOKEN_QUOTE;
  
  //UQ64x96
  uint160 public immutable SQRT_PRICE_RATE_X96;

  int24 private _currentUpperTick;
  int24 private _currentLowerTick;
  uint128 private _liquidity;

  constructor(
    address collateralToken, 
    uint160 sqrtPriceRateRangeX96,
    bool baseToken0
  ) {
    COLLATERAL_TOKEN = collateralToken;
    (address token0, address token1) = _getTokensInColateral();
    TOKEN_BASE = baseToken0 ? token0 : token1;
    TOKEN_QUOTE = baseToken0 ? token1 : token0;
    SQRT_PRICE_RATE_X96 = sqrtPriceRateRangeX96;
    BASE_TOKEN_0 = baseToken0;
  }

  function _decompose() internal returns (uint baseAmountRecieved, uint quoteAmountRecieved) {
    uint amount0Recieved;
    uint amount1Recieved;
    if (_liquidity > 0) {
      (amount0Recieved, amount1Recieved) = IUniswapV3Pool(COLLATERAL_TOKEN).burn(
        _currentLowerTick, 
        _currentUpperTick, 
        _liquidity
      );
      IUniswapV3Pool(COLLATERAL_TOKEN).collect(
        address(this),
        _currentLowerTick,
        _currentUpperTick,
        uint128(amount0Recieved),
        uint128(amount1Recieved)
      );
      baseAmountRecieved = BASE_TOKEN_0 ? amount0Recieved : amount1Recieved;
      quoteAmountRecieved = BASE_TOKEN_0 ? amount1Recieved : amount0Recieved;
    }
      
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

  
  /// @notice Calculates the highest squared root price as Q64.96 from current price and price range rate
  /// @param sqrtPriceX96 The current sqrt ratio as a Q64.96
  /// sqrtRateX96 The sqrt price range rate for which to compute the square root high price as a Q64.96
  /// @return sqrtHighPriceX96 The squared high low price as a Q64.96
  function _calSqrtHighPrice(uint160 sqrtPriceX96, uint160 sqrtRateX96) internal pure returns (uint160) {
    return uint160((uint256(sqrtPriceX96) * uint256(sqrtRateX96 >> 32)) >> 64);
  }

  /// @notice Calculates the lowest squared root price as Q64.96 from current price and price range rate
  /// @param sqrtPriceX96 The current sqrt ratio as a Q64.96
  /// sqrtRateX96 The sqrt price range rate for which to compute the square root low price as a Q64.96
  /// @return sqrtLowPriceX96 The squared root low price as a Q64.96
  function _calSqrtLowPrice(uint160 sqrtPriceX96, uint160 sqrtRateX96) internal pure returns (uint160) {
    return uint160((uint256(sqrtPriceX96) << 96) / uint256(sqrtRateX96));
  }

  function _token0() internal view returns (address) {
    return BASE_TOKEN_0 ? TOKEN_BASE : TOKEN_QUOTE;
  }

  function _token1() internal view returns (address) {
    return BASE_TOKEN_0 ? TOKEN_QUOTE : TOKEN_BASE;
  }

  function uniswapV3MintCallback(
    uint256 amount0Owed,
    uint256 amount1Owed,
    bytes calldata
  ) external override {
    require(msg.sender == COLLATERAL_TOKEN, "Invalid Caller");
    if (amount0Owed > 0)
      TransferHelper.safeTransfer(_token0(), msg.sender, amount0Owed);
    if (amount1Owed > 0)
      TransferHelper.safeTransfer(_token1(), msg.sender, amount1Owed);
  }

  //TODO: Condition?
  function recompose(uint baseAmountDesired, uint quoteAmountDesired) external {
    //TODO: Decompose
    (uint256 baseAmountRecieved, uint256 quoteAmountRecieved) = _decompose();

    baseAmountDesired += baseAmountRecieved;
    quoteAmountDesired += quoteAmountRecieved;

    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(COLLATERAL_TOKEN).slot0();
    uint160 sqrtHiPriceX96 = _calSqrtHighPrice(sqrtPriceX96, SQRT_PRICE_RATE_X96);
    uint160 sqrtLoPriceX96 = _calSqrtLowPrice(sqrtPriceX96, SQRT_PRICE_RATE_X96);

    int24 upperTick = sqrtHiPriceX96.getTickAtSqrtRatio() / 10 * 10;
    int24 lowerTick = sqrtLoPriceX96.getTickAtSqrtRatio() / 10 * 10;

    //TODO: calculate liquidity base on baseAmountDesired and quoteAmountDesired
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(lowerTick),
      TickMath.getSqrtRatioAtTick(upperTick),
      BASE_TOKEN_0 ? baseAmountDesired : quoteAmountDesired,
      BASE_TOKEN_0 ? quoteAmountDesired : baseAmountDesired
    );
    IUniswapV3Pool(COLLATERAL_TOKEN).mint(
      address(this), 
      lowerTick,
      upperTick, 
      liquidity, 
      bytes("")
    );
    // Update state
    _liquidity = liquidity;
    _currentLowerTick = lowerTick;
    _currentUpperTick = upperTick;
  }

  function liquidityValueInQuote() external view returns (uint256) {
    (uint160 sqrtPriceX96, int24 tick,,,,,) = IUniswapV3Pool(COLLATERAL_TOKEN).slot0();
    if (_liquidity > 0) {
      uint256 amount0;
      uint256 amount1;
      if (tick < _currentLowerTick) {
        if (BASE_TOKEN_0)
          return 0;
        return SqrtPriceMath.getAmount0Delta(
          TickMath.getSqrtRatioAtTick(_currentLowerTick),
          TickMath.getSqrtRatioAtTick(_currentUpperTick),
          _liquidity,
          true
        );
      } 
      if (tick < _currentUpperTick) {
        amount0 = SqrtPriceMath.getAmount0Delta(
          sqrtPriceX96,
          TickMath.getSqrtRatioAtTick(_currentUpperTick),
          _liquidity,
          true
        );
        amount1 = SqrtPriceMath.getAmount1Delta(
          TickMath.getSqrtRatioAtTick(_currentLowerTick),
          sqrtPriceX96,
          _liquidity,
          true
        );
        uint256 amountBase = BASE_TOKEN_0 ? amount0 : amount1;
        uint256 amountQuote = BASE_TOKEN_0 ? amount1 : amount0;
        // From https://github.com/Uniswap/v3-periphery/blob/6cce88e63e176af1ddb6cc56e029110289622317/contracts/libraries/OracleLibrary.sol#L49
        uint256 priceX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        return amountQuote + (TOKEN_BASE < TOKEN_QUOTE
            ? FullMath.mulDiv(priceX128, amountBase, 1 << 128)
            : FullMath.mulDiv(1 << 128, amountBase, priceX128));
      }
      if (BASE_TOKEN_0)
        return SqrtPriceMath.getAmount1Delta(
          TickMath.getSqrtRatioAtTick(_currentLowerTick),
          TickMath.getSqrtRatioAtTick(_currentUpperTick),
          _liquidity,
          true
        );
    }
    return 0;
  }

  // TODO: remove this in production
  function exhaust(address token) external {
    TransferHelper.safeTransfer(token, msg.sender, IERC20(token).balanceOf(address(this)));
  }
}
