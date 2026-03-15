//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "src/utils/SpotExecutor.sol";
import "src/utils/SimpleSpotExecutor.sol";

// ============ Mock Contracts ============

contract MockToken is ERC20 {

    uint8 private _dec;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _dec = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}

contract SwapRouter is StdCheats {

    using SafeERC20 for IERC20;

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOut) external {
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        deal(address(tokenOut), address(this), amountOut);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    function swapNoTransferIn(IERC20 tokenOut, uint256 amountOut) external {
        deal(address(tokenOut), address(this), amountOut);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }

}

// ============ SpotExecutor Tests ============

contract SpotExecutorTest is Test {

    using SafeERC20 for IERC20;

    event SwapExecuted(IERC20 indexed tokenToSell, IERC20 indexed tokenToBuy, int256 amountIn, int256 amountOut, uint256 price);

    MockToken internal tokenA; // base, 18 decimals
    MockToken internal tokenB; // quote, 6 decimals
    SwapRouter internal router;
    SpotExecutor internal sut;

    function setUp() public {
        tokenA = new MockToken("Base Token", "BASE", 18);
        tokenB = new MockToken("Quote Token", "QUOTE", 6);
        router = new SwapRouter();
        sut = new SpotExecutor();
    }

    // --- Successful swap with base input currency ---

    function testExecuteSwap_BaseInput() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = 2000e6;
        uint256 unit = 1e6; // quote unit

        // Fund the executor with tokenA (tokenToSell)
        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(router),
            router: address(router),
            swapAmount: amountIn,
            swapBytes: swapBytes,
            flashLoanProvider: IERC7399(address(0))
        });

        // Expect the SwapExecuted event
        // price = output.abs().mulDiv(unit, input.abs()) for Base input
        // price = 2000e6 * 1e6 / 1e18 = 2000000 (but let's compute exactly)
        uint256 expectedPrice = (amountOut * unit) / amountIn;
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(IERC20(address(tokenA)), IERC20(address(tokenB)), -int256(amountIn), int256(amountOut), expectedPrice);

        (int256 input, int256 output, uint256 price) =
            sut.executeSwap(IERC20(address(tokenA)), IERC20(address(tokenB)), Currency.Base, unit, execParams);

        // input should be negative (tokens left the executor)
        assertEq(input, -int256(amountIn), "input delta");
        // output should be positive (tokens sent to msg.sender)
        assertEq(output, int256(amountOut), "output amount");
        assertEq(price, expectedPrice, "price");

        // tokenB should have been transferred to this contract (msg.sender)
        assertEq(tokenB.balanceOf(address(this)), amountOut, "msg.sender received tokenB");
        // executor should have no remaining balance
        assertEq(tokenA.balanceOf(address(sut)), 0, "executor tokenA balance");
        assertEq(tokenB.balanceOf(address(sut)), 0, "executor tokenB balance");
    }

    // --- Successful swap with quote input currency ---

    function testExecuteSwap_QuoteInput() public {
        // Selling quote (tokenB) to buy base (tokenA)
        uint256 amountIn = 2000e6;
        uint256 amountOut = 1e18;
        uint256 unit = 1e6; // quote unit

        deal(address(tokenB), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenB, tokenA, amountIn, amountOut);

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(router),
            router: address(router),
            swapAmount: amountIn,
            swapBytes: swapBytes,
            flashLoanProvider: IERC7399(address(0))
        });

        // price = input.abs().mulDiv(unit, output.abs()) for Quote input
        uint256 expectedPrice = (amountIn * unit) / amountOut;

        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(IERC20(address(tokenB)), IERC20(address(tokenA)), -int256(amountIn), int256(amountOut), expectedPrice);

        (int256 input, int256 output, uint256 price) =
            sut.executeSwap(IERC20(address(tokenB)), IERC20(address(tokenA)), Currency.Quote, unit, execParams);

        assertEq(input, -int256(amountIn), "input delta");
        assertEq(output, int256(amountOut), "output amount");
        assertEq(price, expectedPrice, "price");
    }

    // --- Price calculation correctness ---

    function testPriceCalculation_BaseInput_DifferentAmounts() public {
        // Selling 2 BASE (18 dec) for 5000 QUOTE (6 dec)
        // unit = baseUnit = 1e18 (the unit of the base token — used by Contango._executeSwap)
        uint256 amountIn = 2e18;
        uint256 amountOut = 5000e6;
        uint256 unit = 1e18; // baseUnit

        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(router),
            router: address(router),
            swapAmount: amountIn,
            swapBytes: swapBytes,
            flashLoanProvider: IERC7399(address(0))
        });

        (, , uint256 price) = sut.executeSwap(IERC20(address(tokenA)), IERC20(address(tokenB)), Currency.Base, unit, execParams);

        // price = output.abs() * unit / input.abs() = 5000e6 * 1e18 / 2e18 = 2500e6
        assertEq(price, 2500e6, "price for 2 BASE -> 5000 QUOTE");
    }

    // --- Approve and call flow ---

    function testApproveAndCallFlow() public {
        uint256 amountIn = 100e18;
        uint256 amountOut = 200_000e6;

        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(router),
            router: address(router),
            swapAmount: amountIn,
            swapBytes: swapBytes,
            flashLoanProvider: IERC7399(address(0))
        });

        sut.executeSwap(IERC20(address(tokenA)), IERC20(address(tokenB)), Currency.Base, 1e6, execParams);

        // After swap, approval should have been consumed (router pulled the tokens)
        assertEq(tokenA.allowance(address(sut), address(router)), 0, "allowance consumed");
    }

    // --- Arbitrary calldata forwarding ---

    function testArbitraryCalldataForwarding() public {
        // Use a different function signature (swapNoTransferIn) to test calldata forwarding
        // The router creates output tokens without needing input tokens
        uint256 amountIn = 1e18;
        uint256 amountOut = 500e6;

        deal(address(tokenA), address(sut), amountIn);

        // Router pulls tokenA via approval, returns tokenB without using swap() signature
        bytes memory swapBytes =
            abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(router),
            router: address(router),
            swapAmount: amountIn,
            swapBytes: swapBytes,
            flashLoanProvider: IERC7399(address(0))
        });

        (, int256 output,) = sut.executeSwap(IERC20(address(tokenA)), IERC20(address(tokenB)), Currency.Base, 1e18, execParams);

        assertEq(output, int256(amountOut), "output from arbitrary calldata");
    }

}

// ============ SimpleSpotExecutor Tests ============

contract SimpleSpotExecutorTest is Test {

    using SafeERC20 for IERC20;

    event SwapExecuted(IERC20 indexed tokenToSell, IERC20 indexed tokenToBuy, uint256 amountIn, uint256 amountOut);

    error InsufficientAmountOut(uint256 minExpected, uint256 actual);

    MockToken internal tokenA;
    MockToken internal tokenB;
    SwapRouter internal router;
    SimpleSpotExecutor internal sut;

    function setUp() public {
        tokenA = new MockToken("Token A", "TKN_A", 18);
        tokenB = new MockToken("Token B", "TKN_B", 18);
        router = new SwapRouter();
        sut = new SimpleSpotExecutor();
    }

    // --- Successful swap ---

    function testExecuteSwap_Success() public {
        address trader = address(0xb0b);
        uint256 amountIn = 100e18;
        uint256 amountOut = 90e18;

        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(IERC20(address(tokenA)), IERC20(address(tokenB)), amountIn, amountOut);

        uint256 output = sut.executeSwap({
            tokenToSell: IERC20(address(tokenA)),
            tokenToBuy: IERC20(address(tokenB)),
            spender: address(router),
            amountIn: amountIn,
            minAmountOut: amountOut,
            router: address(router),
            swapBytes: swapBytes,
            to: trader
        });

        assertEq(output, amountOut, "returned output");
        assertEq(tokenB.balanceOf(trader), amountOut, "trader received tokenB");
        assertEq(tokenA.balanceOf(address(sut)), 0, "executor tokenA drained");
        assertEq(tokenB.balanceOf(address(sut)), 0, "executor tokenB drained");
    }

    // --- Output sent to specified `to` address ---

    function testExecuteSwap_TransfersToRecipient() public {
        address recipient = makeAddr("recipient");
        uint256 amountIn = 50e18;
        uint256 amountOut = 45e18;

        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        sut.executeSwap({
            tokenToSell: IERC20(address(tokenA)),
            tokenToBuy: IERC20(address(tokenB)),
            spender: address(router),
            amountIn: amountIn,
            minAmountOut: 0,
            router: address(router),
            swapBytes: swapBytes,
            to: recipient
        });

        assertEq(tokenB.balanceOf(recipient), amountOut, "recipient got tokens");
    }

    // --- minAmountOut enforcement: revert on insufficient output ---

    function testExecuteSwap_RevertsOnInsufficientOutput() public {
        uint256 amountIn = 100e18;
        uint256 actualOut = 89e18;
        uint256 minOut = 90e18;

        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, actualOut);

        vm.expectRevert(abi.encodeWithSelector(InsufficientAmountOut.selector, minOut, actualOut));

        sut.executeSwap({
            tokenToSell: IERC20(address(tokenA)),
            tokenToBuy: IERC20(address(tokenB)),
            spender: address(router),
            amountIn: amountIn,
            minAmountOut: minOut,
            router: address(router),
            swapBytes: swapBytes,
            to: address(this)
        });
    }

    // --- minAmountOut = 0 always passes ---

    function testExecuteSwap_ZeroMinAmountOut() public {
        uint256 amountIn = 100e18;
        uint256 amountOut = 1; // tiny output

        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        // Should not revert because minAmountOut = 0
        uint256 output = sut.executeSwap({
            tokenToSell: IERC20(address(tokenA)),
            tokenToBuy: IERC20(address(tokenB)),
            spender: address(router),
            amountIn: amountIn,
            minAmountOut: 0,
            router: address(router),
            swapBytes: swapBytes,
            to: address(this)
        });

        assertEq(output, amountOut, "tiny output accepted");
    }

    // --- Event emission with correct parameters ---

    function testExecuteSwap_EventEmission() public {
        uint256 amountIn = 77e18;
        uint256 amountOut = 42e18;

        deal(address(tokenA), address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        vm.expectEmit(true, true, false, true);
        emit SwapExecuted(IERC20(address(tokenA)), IERC20(address(tokenB)), amountIn, amountOut);

        sut.executeSwap({
            tokenToSell: IERC20(address(tokenA)),
            tokenToBuy: IERC20(address(tokenB)),
            spender: address(router),
            amountIn: amountIn,
            minAmountOut: 0,
            router: address(router),
            swapBytes: swapBytes,
            to: address(this)
        });
    }

    // --- Arbitrary calldata forwarding ---

    function testExecuteSwap_ArbitraryCalldata() public {
        uint256 amountOut = 200e18;

        bytes memory swapBytes = abi.encodeWithSelector(SwapRouter.swapNoTransferIn.selector, tokenB, amountOut);

        uint256 output = sut.executeSwap({
            tokenToSell: IERC20(address(tokenA)),
            tokenToBuy: IERC20(address(tokenB)),
            spender: address(router),
            amountIn: 0,
            minAmountOut: 0,
            router: address(router),
            swapBytes: swapBytes,
            to: address(this)
        });

        assertEq(output, amountOut, "arbitrary calldata worked");
    }

}
