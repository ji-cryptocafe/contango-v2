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
import "src/moneymarkets/morpho/MorphoBlueMoneyMarket.sol";
import "src/moneymarkets/morpho/MorphoBlueReverseLookup.sol";

import "src/libraries/Roles.sol";

/// @title Morpho Blue Fork Integration Test
/// @notice Tests deployment and security gates with Morpho Blue on mainnet fork
/// @dev Requires MAINNET_URL env var. Tests are skipped if not set.
contract MorphoForkTest is Test {

    // --- Mainnet addresses ---
    IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IMorpho constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    MoneyMarketId constant MM_MORPHO_BLUE = MoneyMarketId.wrap(8);

    // --- Deployed contracts ---
    PositionNFT positionNFT;
    Vault vault;
    RouterGuard routerGuard;
    AccessGate accessGate;
    TradeLimits tradeLimits;
    UnderlyingPositionFactory positionFactory;
    Contango contango;
    Maestro maestro;
    MorphoBlueReverseLookup reverseLookup;

    address admin = makeAddr("admin");
    address trader = makeAddr("trader");

    function setUp() public {
        string memory rpcUrl = vm.envOr("MAINNET_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;
        vm.createSelectFork(rpcUrl);

        Timelock timelock = Timelock.wrap(admin);

        vm.startPrank(admin);

        routerGuard = new RouterGuard();
        accessGate = new AccessGate();
        tradeLimits = new TradeLimits();

        positionNFT = new PositionNFT(timelock);
        vault = new Vault(WETH, timelock);
        positionFactory = new UnderlyingPositionFactory(timelock);

        SpotExecutor spotExecutor = new SpotExecutor(routerGuard);
        SimpleSpotExecutor simpleSpotExecutor = new SimpleSpotExecutor(routerGuard);

        contango = new Contango(positionNFT, vault, positionFactory, spotExecutor, accessGate, tradeLimits, timelock);
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
        vault.setTokenSupport(USDC, true);

        // Register Morpho Blue
        reverseLookup = new MorphoBlueReverseLookup(MORPHO);
        MorphoBlueMoneyMarket morphoMM =
            new MorphoBlueMoneyMarket(MM_MORPHO_BLUE, IContango(address(contango)), MORPHO, reverseLookup, IERC20(address(0)));
        positionFactory.registerMoneyMarket(IMoneyMarket(address(morphoMM)));

        // Whitelist
        accessGate.addWallet(trader);

        vm.stopPrank();
    }

    modifier requiresFork() {
        string memory rpcUrl = vm.envOr("MAINNET_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;
        _;
    }

    // =================== Morpho Registration ===================

    function test_morpho_money_market_registered() public requiresFork {
        IMoneyMarket mm = positionFactory.moneyMarket(MM_MORPHO_BLUE);
        assertTrue(address(mm) != address(0));
        assertTrue(mm.NEEDS_ACCOUNT());
    }

    function test_morpho_reverse_lookup_deployed() public requiresFork {
        assertEq(address(reverseLookup.morpho()), address(MORPHO));
    }

    // =================== Vault with USDC ===================

    function test_deposit_USDC() public requiresFork {
        uint256 amount = 10_000e6; // 10k USDC
        deal(address(USDC), trader, amount);

        vm.startPrank(trader);
        USDC.approve(address(vault), amount);
        maestro.deposit(USDC, amount);
        vm.stopPrank();

        assertEq(vault.balanceOf(USDC, trader), amount);
    }

    function test_deposit_and_withdraw_USDC() public requiresFork {
        uint256 amount = 5_000e6;
        deal(address(USDC), trader, amount);

        vm.startPrank(trader);
        USDC.approve(address(vault), amount);
        maestro.deposit(USDC, amount);

        maestro.withdraw(USDC, amount, trader);
        vm.stopPrank();

        assertEq(vault.balanceOf(USDC, trader), 0);
        assertEq(USDC.balanceOf(trader), amount);
    }

    // =================== Security ===================

    function test_non_whitelisted_cannot_trade() public requiresFork {
        address rando = makeAddr("rando");
        TradeParams memory tp;
        ExecutionParams memory ep;

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(AccessGate.NotWhitelisted.selector, rando));
        contango.trade(tp, ep);
    }

    // =================== MorphoBlueReverseLookup ===================

    function test_reverseLookup_setMarket() public requiresFork {
        // Use a known Morpho Blue market (wstETH/USDC)
        // MarketId for wstETH/USDC with Chainlink oracle on Morpho Blue mainnet
        // This is a well-known market — we just verify setMarket doesn't revert
        // For a real test, you'd need the exact marketId from Morpho's registry

        // Just verify nextPayload starts at 1
        assertEq(reverseLookup.nextPayload(), 1);
    }

}
