//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../dependencies/PayableMulticall.sol";
import "../interfaces/IMaestro.sol";
import "../interfaces/IContango.sol";
import "../interfaces/IVault.sol";
import "../libraries/Errors.sol";
import "../libraries/Validations.sol";
import "../libraries/ERC20Lib.sol";
import "../utils/SimpleSpotExecutor.sol";

contract Maestro is IMaestro, PayableMulticall {

    using SignedMath for int256;
    using SafeCast for *;
    using ERC20Lib for *;
    using { validateCreatePositionPermissions, validateModifyPositionPermissions } for PositionNFT;

    uint256 public constant ALL = 0;

    IContango public immutable contango;
    IVault public immutable vault;
    PositionNFT public immutable positionNFT;
    IWETH9 public immutable nativeToken;
    SimpleSpotExecutor public immutable spotExecutor;

    constructor(IContango _contango, IVault _vault, SimpleSpotExecutor _spotExecutor) {
        contango = _contango;
        vault = _vault;
        spotExecutor = _spotExecutor;
        positionNFT = _contango.positionNFT();
        nativeToken = _vault.nativeToken();
    }

    function deposit(IERC20 token, uint256 amount) public payable override returns (uint256) {
        return vault.deposit(token, msg.sender, amount);
    }

    function depositNative() public payable returns (uint256) {
        return vault.depositNative{ value: msg.value }(msg.sender);
    }

    function withdraw(IERC20 token, uint256 amount, address to) public payable override returns (uint256) {
        if (amount == ALL) amount = vault.balanceOf(token, msg.sender);
        if (amount == 0) return 0;
        return vault.withdraw(token, msg.sender, amount, to);
    }

    function withdrawNative(uint256 amount, address to) public payable override returns (uint256) {
        if (amount == ALL) amount = vault.balanceOf(nativeToken, msg.sender);
        if (amount == 0) return 0;
        return vault.withdrawNative(msg.sender, amount, to);
    }

    function trade(TradeParams memory tradeParams, ExecutionParams calldata execParams)
        public
        payable
        returns (PositionId positionId_, Trade memory trade_)
    {
        if (positionNFT.exists(tradeParams.positionId)) positionNFT.validateModifyPositionPermissions(tradeParams.positionId);
        if (tradeParams.cashflow == type(int256).max) {
            tradeParams.cashflow = vault.balanceOf(_cashflowToken(tradeParams), msg.sender).toInt256();
        }
        (positionId_, trade_) = contango.tradeOnBehalfOf(tradeParams, execParams, msg.sender);
    }

    function _cashflowToken(TradeParams memory tradeParams) internal view returns (IERC20 cashflowToken) {
        Instrument memory instrument = contango.instrument(tradeParams.positionId.getSymbol());
        cashflowToken = tradeParams.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;
    }

    receive() external payable {
        if (msg.sender != address(nativeToken)) revert SenderIsNotNativeToken(msg.sender, address(nativeToken));
    }

}
