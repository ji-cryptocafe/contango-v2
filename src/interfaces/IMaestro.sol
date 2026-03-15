//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../libraries/DataTypes.sol";
import "../utils/SimpleSpotExecutor.sol";
import { IPermit2 } from "../dependencies/Uniswap.sol";
import "./IContango.sol";
import "./IVault.sol";

struct SwapData {
    address router;
    address spender;
    uint256 amountIn;
    uint256 minAmountOut;
    bytes swapBytes;
}

interface IMaestro is IContangoErrors, IVaultErrors {

    error InvalidCashflow();
    error NotNativeToken(IERC20 token);

    function contango() external view returns (IContango);
    function vault() external view returns (IVault);
    function positionNFT() external view returns (PositionNFT);
    function nativeToken() external view returns (IWETH9);
    function spotExecutor() external view returns (SimpleSpotExecutor);

    // =================== Funding primitives ===================

    function deposit(IERC20 token, uint256 amount) external payable returns (uint256);

    function depositNative() external payable returns (uint256);

    function withdraw(IERC20 token, uint256 amount, address to) external payable returns (uint256);

    function withdrawNative(uint256 amount, address to) external payable returns (uint256);

    // =================== Trading actions ===================

    function trade(TradeParams calldata tradeParams, ExecutionParams calldata execParams)
        external
        payable
        returns (PositionId, Trade memory);

}
