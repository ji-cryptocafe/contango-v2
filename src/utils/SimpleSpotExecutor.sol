//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../libraries/ERC20Lib.sol";
import "../security/RouterGuard.sol";

interface SimpleSpotExecutorEvents {

    event SwapExecuted(IERC20 indexed tokenToSell, IERC20 indexed tokenToBuy, uint256 amountIn, uint256 amountOut);

}

interface SimpleSpotExecutorErrors {

    error InsufficientAmountOut(uint256 minExpected, uint256 actual);

}

contract SimpleSpotExecutor is SimpleSpotExecutorEvents, SimpleSpotExecutorErrors {

    RouterGuard public immutable routerGuard;

    constructor(RouterGuard _routerGuard) {
        routerGuard = _routerGuard;
    }

    function executeSwap(
        IERC20 tokenToSell,
        IERC20 tokenToBuy,
        address spender,
        uint256 amountIn,
        uint256 minAmountOut,
        address router,
        bytes calldata swapBytes,
        address to
    ) external returns (uint256 output) {
        routerGuard.validateRouter(router);
        routerGuard.validateSpender(spender);

        SafeERC20.forceApprove(tokenToSell, spender, amountIn);
        Address.functionCall(router, swapBytes);
        SafeERC20.forceApprove(tokenToSell, spender, 0); // clear residual approval

        output = ERC20Lib.transferBalance(tokenToBuy, to);
        if (output < minAmountOut) revert InsufficientAmountOut(minAmountOut, output);

        emit SwapExecuted(tokenToSell, tokenToBuy, amountIn, output);
    }

}
