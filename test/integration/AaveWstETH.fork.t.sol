// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/core/Contango.sol";
import "src/core/Maestro.sol";
import "src/core/Vault.sol";
import "src/core/PositionNFT.sol";

import "src/security/AccessGate.sol";
import "src/security/RouterGuard.sol";
import "src/security/TradeLimits.sol";

import "src/utils/SpotExecutor.sol";
import "src/utils/SimpleSpotExecutor.sol";

import "src/moneymarkets/UnderlyingPositionFactory.sol";
import "src/moneymarkets/aave/AaveMoneyMarket.sol";

import "src/libraries/Roles.sol";

/// @title Aave V3 wstETH/ETH Fork Integration Test
/// @notice Tests full position lifecycle on mainnet fork: deposit → open → close → withdraw
/// @dev Requires MAINNET_URL env var. Tests are skipped if not set.
contract AaveWstETHForkTest is Test {

    // --- Mainnet addresses ---
    IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IPoolAddressesProvider constant AAVE_PROVIDER =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    IAaveRewardsController constant AAVE_REWARDS =
        IAaveRewardsController(0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb);
    MoneyMarketId constant MM_AAVE = MoneyMarketId.wrap(1);

    // --- Deployed contracts ---
    PositionNFT positionNFT;
    Vault vault;
    RouterGuard routerGuard;
    AccessGate accessGate;
    TradeLimits tradeLimits;
    SpotExecutor spotExecutor;
    SimpleSpotExecutor simpleSpotExecutor;
    UnderlyingPositionFactory positionFactory;
    Contango contango;
    Maestro maestro;

    address admin = makeAddr("admin");
    address trader;
    uint256 traderKey;

    Symbol constant SYMBOL = Symbol.wrap("wstETH/ETH");

    function setUp() public {
        // Fork mainnet
        string memory rpcUrl = vm.envOr("MAINNET_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            // Skip all tests if no RPC
            return;
        }
        vm.createSelectFork(rpcUrl);

        (trader, traderKey) = makeAddrAndKey("trader");
        Timelock timelock = Timelock.wrap(admin);

        // Deploy full stack
        vm.startPrank(admin);

        routerGuard = new RouterGuard();
        accessGate = new AccessGate();
        tradeLimits = new TradeLimits();

        positionNFT = new PositionNFT(timelock);
        vault = new Vault(WETH, timelock);
        positionFactory = new UnderlyingPositionFactory(timelock);

        spotExecutor = new SpotExecutor(routerGuard);
        simpleSpotExecutor = new SimpleSpotExecutor(routerGuard);

        contango = new Contango(positionNFT, vault, positionFactory, spotExecutor, accessGate, tradeLimits, timelock);
        tradeLimits.setContango(address(contango));
        maestro = new Maestro(IContango(address(contango)), vault, simpleSpotExecutor);

        // Roles
        vault.grantRole(OPERATOR_ROLE, admin);
        vault.grantRole(CONTANGO_ROLE, address(contango));
        vault.grantRole(CONTANGO_ROLE, address(maestro));
        positionNFT.grantRole(MINTER_ROLE, address(contango));
        positionNFT.setContangoContract(address(maestro), true);
        positionFactory.grantRole(CONTANGO_ROLE, address(contango));
        contango.grantRole(OPERATOR_ROLE, admin);

        // Token support
        vault.setTokenSupport(WSTETH, true);

        // Register Aave V3
        AaveMoneyMarket aaveMM =
            new AaveMoneyMarket(MM_AAVE, IContango(address(contango)), AAVE_PROVIDER, AAVE_REWARDS, true);
        positionFactory.registerMoneyMarket(IMoneyMarket(address(aaveMM)));

        // Create instrument
        contango.createInstrument(SYMBOL, WSTETH, IERC20(address(WETH)));

        // Whitelist trader
        accessGate.addWallet(trader);

        vm.stopPrank();
    }

    modifier requiresFork() {
        string memory rpcUrl = vm.envOr("MAINNET_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            return;
        }
        _;
    }

    // =================== Vault Operations ===================

    function test_deposit_ETH() public requiresFork {
        uint256 amount = 10 ether;
        deal(trader, amount);

        vm.prank(trader);
        maestro.depositNative{ value: amount }();

        assertEq(vault.balanceOf(IERC20(address(WETH)), trader), amount, "vault balance");
    }

    function test_deposit_and_withdraw_ETH() public requiresFork {
        uint256 amount = 5 ether;
        deal(trader, amount);

        vm.startPrank(trader);
        maestro.depositNative{ value: amount }();
        assertEq(vault.balanceOf(IERC20(address(WETH)), trader), amount);

        maestro.withdrawNative(amount, trader);
        vm.stopPrank();

        assertEq(vault.balanceOf(IERC20(address(WETH)), trader), 0);
        assertEq(trader.balance, amount);
    }

    // =================== Security Gates ===================

    function test_trade_reverts_for_non_whitelisted() public requiresFork {
        address rando = makeAddr("rando");

        // Build a positionId for wstETH/ETH on Aave (perp, number=0)
        PositionId positionId = PositionId.wrap(
            bytes32(uint256(uint128(Symbol.unwrap(SYMBOL))) << 128 | uint256(MoneyMarketId.unwrap(MM_AAVE)) << 120
                | uint256(type(uint32).max) << 88)
        );

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: 1 ether,
            limitPrice: 0,
            cashflowCcy: Currency.Quote,
            cashflow: 1 ether
        });

        ExecutionParams memory execParams;

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(AccessGate.NotWhitelisted.selector, rando));
        contango.trade(tradeParams, execParams);
    }

    function test_trade_reverts_for_unwhitelisted_router() public requiresFork {
        address fakeRouter = makeAddr("fakeRouter");

        PositionId positionId = PositionId.wrap(
            bytes32(uint256(uint128(Symbol.unwrap(SYMBOL))) << 128 | uint256(MoneyMarketId.unwrap(MM_AAVE)) << 120
                | uint256(type(uint32).max) << 88)
        );

        // Deposit some ETH first
        deal(trader, 10 ether);
        vm.prank(trader);
        maestro.depositNative{ value: 10 ether }();

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: 1 ether,
            limitPrice: type(uint256).max,
            cashflowCcy: Currency.Quote,
            cashflow: 5 ether
        });

        ExecutionParams memory execParams = ExecutionParams({
            spender: fakeRouter,
            router: fakeRouter,
            swapAmount: 5 ether,
            swapBytes: "",
            flashLoanProvider: IERC7399(address(0))
        });

        // Should revert at RouterGuard level
        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(RouterGuard.RouterNotAllowed.selector, fakeRouter));
        maestro.trade(tradeParams, execParams);
    }

    // =================== Instrument Queries ===================

    function test_instrument_created() public requiresFork {
        Instrument memory inst = contango.instrument(SYMBOL);
        assertEq(address(inst.base), address(WSTETH));
        assertEq(address(inst.quote), address(WETH));
        assertFalse(inst.closingOnly);
    }

    // =================== Position Factory ===================

    function test_aave_money_market_registered() public requiresFork {
        IMoneyMarket mm = positionFactory.moneyMarket(MM_AAVE);
        assertTrue(address(mm) != address(0));
        assertEq(MoneyMarketId.unwrap(mm.moneyMarketId()), MoneyMarketId.unwrap(MM_AAVE));
        assertTrue(mm.NEEDS_ACCOUNT());
    }

}
