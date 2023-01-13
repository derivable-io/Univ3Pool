// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IPool.sol";
import "./interfaces/ILogic.sol";
import "./interfaces/IPoolFactory.sol";

contract Pool is ERC1155Supply, IPool {
    event TokenAdded(address indexed acc, uint indexed id);
    event TokenRemoved(address indexed acc, uint indexed id);

    address public immutable COLLATERAL_TOKEN;
    address public immutable TOKEN0;
    address public immutable TOKEN1;
    address public immutable LOGIC;
    address immutable FEE_RECIPIENT;
    uint immutable FEE_NUM;
    uint immutable FEE_DENOM;
    int24 immutable TICK_SPREAD;

    int24 private constant TICK_DENOM = 10000;
    uint private constant CTOKEN_ID = 0x20000;
    uint private constant CP_ID =  0x10000;

    int24 private _currentUpperTick;
    int24 private _currentLowerTick;
    uint128 private _liquidity;

    event PoolCreated(
        address indexed logic,
        bytes32 indexed app,    // always "DDL"
        address         feeRecipient,
        uint            feeNum,
        uint            feeDenom
    );

    event Swap(
        address indexed recipient,
        uint    indexed idIn,
        uint    indexed idOut,
        uint            amountOut,
        uint            fee
    );

    constructor(address logic, int24 tickSpread)
    ERC1155('') {
        // // TODO: alow custom URI to be passed here in pool config
        LOGIC = logic;
        COLLATERAL_TOKEN = ILogic(LOGIC).COLLATERAL_TOKEN();
        (TOKEN0, TOKEN1) = _getTokensInColateral();
        (FEE_RECIPIENT, FEE_NUM, FEE_DENOM) = IPoolFactory(msg.sender).getFeeInfo();
        TICK_SPREAD = tickSpread;
        emit PoolCreated(
            logic,
            "DDL",
            FEE_RECIPIENT,
            FEE_NUM,
            FEE_DENOM
        );
    }

    /**
     * @dev See {ERC1155-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        if (to == address(0)) {
            return;
        }
        for (uint i = 0; i < ids.length; i++) {
            if (balanceOf(to, ids[i]) == 0) {
                emit TokenAdded(to, ids[i]);
            }
        }
    }

    /**
     * @dev See {ERC1155-_afterTokenTransfer}.
     */
    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);
        if (from == address(0)) {
            return;
        }
        for (uint i = 0; i < ids.length; i++) {
            if (balanceOf(from, ids[i]) == 0) {
                emit TokenRemoved(from, ids[i]);
            }
        }
    }


    function _decompose() internal returns (uint amount0Recieved, uint amount1Recieved) {
        (amount0Recieved, amount1Recieved) = IUniswapV3Pool(COLLATERAL_TOKEN).burn(
            _currentLowerTick, 
            _currentUpperTick, 
            _liquidity
        );
    }

    function _compose(int24 tick) internal returns (uint amount0Used, uint amount1Used) {
        uint _amount0 = IERC20(TOKEN0).balanceOf(address(this));
        uint _amount1 = IERC20(TOKEN1).balanceOf(address(this));

        //TODO: calculate the amount to transfer to mint LP
        _safeTransferFrom(TOKEN0, address(this), address(this), _amount0);
        _safeTransferFrom(TOKEN1, address(this), address(this), _amount1);
        //TODO: calculate the liquidity amount to mint
        _liquidity = 0;

        //Calculate tick
        _currentLowerTick = tick * (TICK_DENOM - TICK_SPREAD) / TICK_DENOM;
        _currentUpperTick = tick * (TICK_DENOM + TICK_SPREAD) / TICK_DENOM;
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
    ) external override returns (uint amountOut, uint fee) {
        bool needVerifying;
        (amountOut, needVerifying) = ILogic(LOGIC).swap(idIn, idOut);
        // TODO: Compare idOut with base and quote
        if (idOut == CTOKEN_ID) {
            // TODO: fee can be get-arounded if LOGIC don't use the POOL token
            if (idIn == CP_ID) {
                fee = amountOut * FEE_NUM / FEE_DENOM;
                if (fee > 0) {
                    // Charge fee in which token or we skip it for now?
                    amountOut -= fee;
                }
            }
            /* TODO: idOut == BASE_ID or QUOTE
            - If amountOut < token in pool: transfer to recipient
            - Else: 
                + Decompse
                + Transfer token to recipient
                + compose?
            */

        } else {
            _mint(recipient, idOut, amountOut, '');
        }

        if (idIn == CTOKEN_ID) {
            // nothing to do
        } else {
            _burn(address(this), idIn, balanceOf(address(this), idIn));
        }

        if (needVerifying) {
            ILogic(LOGIC).verify();
        }

        emit Swap(recipient, idIn, idOut, amountOut, fee);
    }

    //TODO: Condition?
    function compose(int24 tick) external returns (uint amount0Used, uint amount1Used) {
        (amount0Used, amount1Used) = _compose(tick);
    }

    //TODO: Condition?
    function decompose() external returns (uint amount0Recieved, uint amount1Recieved) {
        (amount0Recieved, amount1Recieved) = _decompose();
    }

    // TODO: remove this in production
    function exhaust(address token) external {
        require(msg.sender == FEE_RECIPIENT, "DDL: UNAUTHORIZED");
        TransferHelper.safeTransfer(token, FEE_RECIPIENT, IERC20(token).balanceOf(address(this)));
    }
}
