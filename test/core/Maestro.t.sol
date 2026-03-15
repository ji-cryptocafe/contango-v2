//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import "forge-std/console.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract MaestroTest is BaseTest, GasSnapshot {

    using SignedMath for *;
    using SafeCast for *;

    Env internal env;
    TestInstrument internal instrument;
    PositionActions internal positionActions;

    IVault internal vault;
    Maestro internal maestro;
    Contango internal contango;
    PositionNFT internal positionNFT;
    SwapRouter02 internal router;
    address internal spotExecutor;

    IERC20 internal usdc;
    IERC20 internal weth;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        positionActions = env.positionActions();

        vault = env.vault();
        maestro = env.maestro();
        contango = env.contango();
        positionNFT = contango.positionNFT();
        router = env.uniswapRouter();
        spotExecutor = address(maestro.spotExecutor());

        usdc = env.token(USDC);
        weth = env.token(WETH);

        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function testDeposit() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));

        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testDepositNative() public {
        vm.deal(TRADER, 10 ether);

        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        assertEq(vault.balanceOf(weth, TRADER), 10 ether, "trader vault balance");
    }

    function testDepositValidations() public {
        // token not registered
        IERC20 arb = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548); // ARB on arbitrum

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.UnsupportedToken.selector, arb));
        vm.prank(TRADER);
        maestro.deposit(arb, 10_000e18);
    }

    function testWithdraw_ExactAmount() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        vm.prank(TRADER);
        maestro.withdraw(usdc, 10_000e6, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 10_000e6, "trader balance");
    }

    function testWithdraw_PartialAmount() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        vm.prank(TRADER);
        snapStart("Maestro:Withdraw_PartialAmount");
        maestro.withdraw(usdc, 5000e6, TRADER);
        snapEnd();

        assertEq(vault.balanceOf(usdc, TRADER), 5000e6, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 5000e6, "trader balance");
    }

    function testWithdraw_All() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        vm.prank(TRADER);
        maestro.withdraw(usdc, 0, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 10_000e6, "trader balance");
    }

    function testWithdrawNative_ExactAmount() public {
        vm.deal(TRADER, 10 ether);
        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        vm.prank(TRADER);
        maestro.withdrawNative(10 ether, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 10 ether, "trader balance");
    }

    function testWithdrawNative_PartialAmount() public {
        vm.deal(TRADER, 10 ether);
        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        vm.prank(TRADER);
        maestro.withdrawNative(5 ether, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 5 ether, "trader vault balance");
        assertEq(TRADER.balance, 5 ether, "trader balance");
    }

    function testWithdrawNative_All() public {
        vm.deal(TRADER, 10 ether);
        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        vm.prank(TRADER);
        maestro.withdrawNative(0, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 10 ether, "trader balance");
    }

    function testTradeWithBalance() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4000e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);
        tradeParams.cashflow = type(int256).max;

        vm.prank(TRADER);
        (PositionId positionId,) = maestro.trade(tradeParams, executionParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
    }

    function testDepositAndTradeNative_multicallEdition() public {
        vm.deal(TRADER, 4 ether);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Base, 4 ether);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IMaestro.depositNative.selector);
        data[1] = abi.encodeWithSelector(IMaestro.trade.selector, tradeParams, executionParams);

        vm.prank(TRADER);
        (bytes[] memory results) = maestro.multicall{ value: 4 ether }(data);

        PositionId positionId = abi.decode(results[1], (PositionId));

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
    }

    function _prepareCloseTrade(PositionId positionId, Currency cashflowCcy)
        internal
        returns (TradeParams memory tradeParams, ExecutionParams memory executionParams)
    {
        return _prepareCloseTrade(10 ether, positionId, cashflowCcy);
    }

    function _prepareCloseTrade(uint256 quantity, PositionId positionId, Currency cashflowCcy)
        internal
        returns (TradeParams memory tradeParams, ExecutionParams memory executionParams)
    {
        TSQuote memory quote = positionActions.quoteTrade({
            positionId: positionId,
            quantity: -int256(quantity),
            leverage: 0,
            cashflow: 0,
            cashflowCcy: cashflowCcy
        });

        tradeParams = quote.tradeParams;
        executionParams = quote.execParams;
    }

    function _prepareTrade(Currency cashflowCcy, int256 cashflow)
        internal
        returns (TradeParams memory tradeParams, ExecutionParams memory executionParams)
    {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        TSQuote memory quote =
            positionActions.quoteWithCashflow({ positionId: positionId, quantity: 10 ether, cashflow: cashflow, cashflowCcy: cashflowCcy });

        tradeParams = quote.tradeParams;
        executionParams = quote.execParams;
    }

}
