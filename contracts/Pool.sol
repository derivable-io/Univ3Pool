// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPool.sol";
import "./interfaces/ILogic.sol";
import "./interfaces/IPoolFactory.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

abstract contract Pool is ERC1155Supply, IPool {
    event TokenAdded(address indexed acc, uint indexed id);
    event TokenRemoved(address indexed acc, uint indexed id);

    address public immutable COLLATERAL_TOKEN;
    address public immutable TOKEN0;
    address public immutable TOKEN1;
    address public immutable LOGIC;
    address immutable FEE_RECIPIENT;
    uint immutable FEE_NUM;
    uint immutable FEE_DENOM;

    uint private constant CTOKEN_ID = 0x20000;
    uint private constant CP_ID =  0x10000;

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

    constructor(address logic)
    ERC1155('') {
        // // TODO: alow custom URI to be passed here in pool config
        // string memory uri = string(
        //     abi.encodePacked(
        //         'https://derivable.io/metadata/',
        //         address(this),
        //         '/{id}.json'
        //     )
        // );
        // _setURI(uri);
        LOGIC = logic;
        COLLATERAL_TOKEN = ILogic(LOGIC).COLLATERAL_TOKEN();
        (TOKEN0, TOKEN1) = this._getTokensInColateral();
        (FEE_RECIPIENT, FEE_NUM, FEE_DENOM) = IPoolFactory(msg.sender).getFeeInfo();
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
                + Recompose?
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

    function _getTokensInColateral() internal virtual returns (address token1, address token2);

    // TODO: remove this in production
    function exhaust(address token) external {
        require(msg.sender == FEE_RECIPIENT, "DDL: UNAUTHORIZED");
        TransferHelper.safeTransfer(token, FEE_RECIPIENT, IERC20(token).balanceOf(address(this)));
    }
}
