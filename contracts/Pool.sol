// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IPool.sol";

contract Pool is ERC1155Supply, IPool {
    address public immutable COLLATERAL_TOKEN;
    address public immutable TOKEN0;
    address public immutable TOKEN1;
    uint private constant CP_ID =  0x10000;
    uint private constant CTOKEN0_ID = 0x20000;
    uint private constant CTOKEN1_ID = 0x30000;

    int24 private _currentUpperTick;
    int24 private _currentLowerTick;
    uint128 private _liquidity;

    constructor(address collateralToken)
    ERC1155('') {
        // // TODO: alow custom URI to be passed here in pool config
        COLLATERAL_TOKEN = collateralToken;
        (TOKEN0, TOKEN1) = _getTokensInColateral();
    }

    function _decompose() internal returns (uint amount0Recieved, uint amount1Recieved) {
        (amount0Recieved, amount1Recieved) = IUniswapV3Pool(COLLATERAL_TOKEN).burn(
            _currentLowerTick, 
            _currentUpperTick, 
            _liquidity
        );
    }

    function _compose(int24 lowerTick, int24 upperTick) internal returns (uint amount0Used, uint amount1Used) {
        uint _amount0 = IERC20(TOKEN0).balanceOf(address(this));
        uint _amount1 = IERC20(TOKEN1).balanceOf(address(this));

        //TODO: calculate the amount to transfer to mint LP
        _safeTransferFrom(TOKEN0, address(this), address(this), _amount0);
        _safeTransferFrom(TOKEN1, address(this), address(this), _amount1);

        //

        //TODO: calculate the liquidity amount to mint
        _liquidity = 0;

        //

        _currentLowerTick = lowerTick;
        _currentUpperTick = upperTick;
        (amount0Used, amount1Used) = IUniswapV3Pool(COLLATERAL_TOKEN).mint(
            address(this), 
            _currentLowerTick,
            _currentUpperTick, 
            _liquidity, 
            bytes("")
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

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /// @dev require amountIn is transfered here first
    function swap(
        uint idIn,
        uint idOut,
        address recipient
    ) external override returns (uint amountOut) {
        // TODO: Compare idOut with base and quote
        if (idOut == CTOKEN0_ID) {
            /* TODO: idOut == BASE_ID or QUOTE
            - If amountOut < token in pool: transfer to recipient
            - Else: 
                + Decompse
                + Transfer token to recipient
                + compose?
            */
        } else if (idOut == CTOKEN1_ID) {
            
        } else {
            _mint(recipient, idOut, amountOut, '');
        }

        if (idIn == CTOKEN0_ID || idIn == CTOKEN1_ID) {
            // nothing to do
        } else {
            _burn(address(this), idIn, balanceOf(address(this), idIn));
        }
    }

    //TODO: Condition?
    function compose(int24 lowerTick, int24 upperTick) external returns (uint amount0Used, uint amount1Used) {
        (amount0Used, amount1Used) = _compose(lowerTick, upperTick);
    }

    //TODO: Condition?
    function decompose() external returns (uint amount0Recieved, uint amount1Recieved) {
        (amount0Recieved, amount1Recieved) = _decompose();
    }

    // TODO: remove this in production
    function exhaust(address token) external {
        TransferHelper.safeTransfer(token, msg.sender, IERC20(token).balanceOf(address(this)));
    }
}
