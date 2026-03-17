// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

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
import "src/moneymarkets/morpho/MorphoBlueMoneyMarket.sol";
import "src/moneymarkets/morpho/MorphoBlueReverseLookup.sol";

import "src/dependencies/IWETH9.sol";

/// @title Deploy — Full deployment of the stripped Contango fork
/// @notice Deploys all contracts, grants roles, whitelists wallets/routers, creates instruments
/// @dev Usage:
///   forge script script/Deploy.s.sol:Deploy --rpc-url $MAINNET_URL --broadcast --verify
///
/// Required env vars: DEPLOYER_PRIVATE_KEY, ADMIN_ADDRESS
/// Optional env vars: WHITELISTED_WALLETS, KYBERSWAP_ROUTER, FLASH_LOAN_PROVIDER,
///                    MAX_TRADE_SIZE, MAX_DAILY_VOLUME, MAX_OPEN_POSITIONS
contract Deploy is Script {

    // --- Mainnet addresses ---
    IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Aave V3 mainnet
    IPoolAddressesProvider constant AAVE_ADDRESSES_PROVIDER =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    IAaveRewardsController constant AAVE_REWARDS =
        IAaveRewardsController(0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb);
    MoneyMarketId constant MM_AAVE = MoneyMarketId.wrap(1);

    // Morpho Blue mainnet
    IMorpho constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    MoneyMarketId constant MM_MORPHO_BLUE = MoneyMarketId.wrap(8);

    // --- Deployed contracts ---
    PositionNFT public positionNFT;
    Vault public vault;
    RouterGuard public routerGuard;
    AccessGate public accessGate;
    TradeLimits public tradeLimits;
    SpotExecutor public spotExecutor;
    SimpleSpotExecutor public simpleSpotExecutor;
    UnderlyingPositionFactory public positionFactory;
    Contango public contango;
    Maestro public maestro;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        Timelock timelock = Timelock.wrap(admin);

        vm.startBroadcast(deployerKey);

        // 1. Security contracts
        routerGuard = new RouterGuard();
        accessGate = new AccessGate();
        tradeLimits = new TradeLimits();

        // 2. Core infrastructure
        positionNFT = new PositionNFT(timelock);
        vault = new Vault(WETH, timelock);
        positionFactory = new UnderlyingPositionFactory(timelock);

        // 3. Executors (with RouterGuard)
        spotExecutor = new SpotExecutor(routerGuard);
        simpleSpotExecutor = new SimpleSpotExecutor(routerGuard);

        // 4. Contango (main engine)
        contango = new Contango(positionNFT, vault, positionFactory, spotExecutor, accessGate, tradeLimits, timelock);
        tradeLimits.setContango(address(contango));

        // 5. Maestro (user entry point)
        maestro = new Maestro(contango, vault, simpleSpotExecutor);

        // 6. Grant roles
        positionNFT.grantRole(positionNFT.DEFAULT_ADMIN_ROLE(), admin);
        vault.grantRole(OPERATOR_ROLE, admin);
        vault.grantRole(CONTANGO_ROLE, address(contango));
        vault.grantRole(CONTANGO_ROLE, address(maestro));
        positionNFT.grantRole(MINTER_ROLE, address(contango));
        positionNFT.setContangoContract(address(maestro), true);
        positionFactory.grantRole(CONTANGO_ROLE, address(contango));
        contango.grantRole(OPERATOR_ROLE, admin);

        // 7. Token support
        vault.setTokenSupport(WSTETH, true);
        vault.setTokenSupport(USDC, true);

        // 8. Register money markets
        _deployAndRegisterAave(timelock);
        _deployAndRegisterMorpho(timelock);

        // 9. Whitelist routers (KyberSwap)
        _configureRouterGuard();

        // 10. Whitelist wallets
        _configureAccessGate();

        // 11. Trade limits
        _configureTradeLimits();

        // 12. Create instruments
        _createInstruments();

        // 13. Transfer security contract ownership to admin (use timelock/multisig in production)
        routerGuard.transferOwnership(admin);
        accessGate.transferOwnership(admin);
        tradeLimits.transferOwnership(admin);

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("=== Deployed Addresses ===");
        console.log("PositionNFT:       ", address(positionNFT));
        console.log("Vault:             ", address(vault));
        console.log("RouterGuard:       ", address(routerGuard));
        console.log("AccessGate:        ", address(accessGate));
        console.log("TradeLimits:       ", address(tradeLimits));
        console.log("SpotExecutor:      ", address(spotExecutor));
        console.log("SimpleSpotExecutor:", address(simpleSpotExecutor));
        console.log("PositionFactory:   ", address(positionFactory));
        console.log("Contango:          ", address(contango));
        console.log("Maestro:           ", address(maestro));
    }

    function _deployAndRegisterAave(Timelock) internal {
        AaveMoneyMarket aaveMM =
            new AaveMoneyMarket(MM_AAVE, IContango(address(contango)), AAVE_ADDRESSES_PROVIDER, AAVE_REWARDS, true);
        positionFactory.registerMoneyMarket(IMoneyMarket(address(aaveMM)));
        console.log("AaveMoneyMarket:   ", address(aaveMM));
    }

    function _deployAndRegisterMorpho(Timelock) internal {
        MorphoBlueReverseLookup reverseLookup = new MorphoBlueReverseLookup(MORPHO);
        MorphoBlueMoneyMarket morphoMM =
            new MorphoBlueMoneyMarket(MM_MORPHO_BLUE, IContango(address(contango)), MORPHO, reverseLookup, IERC20(address(0)));
        positionFactory.registerMoneyMarket(IMoneyMarket(address(morphoMM)));
        console.log("MorphoReverseLookup:", address(reverseLookup));
        console.log("MorphoMoneyMarket: ", address(morphoMM));
    }

    function _configureRouterGuard() internal {
        address kyberRouter = vm.envOr("KYBERSWAP_ROUTER", address(0));
        if (kyberRouter != address(0)) {
            routerGuard.setRouter(kyberRouter, true);
            routerGuard.setSpender(kyberRouter, true);
            console.log("KyberSwap router whitelisted:", kyberRouter);
        }

        address flp = vm.envOr("FLASH_LOAN_PROVIDER", address(0));
        if (flp != address(0)) {
            routerGuard.setFlashLoanProvider(flp, true);
            console.log("Flash loan provider whitelisted:", flp);
        }
    }

    function _configureAccessGate() internal {
        string memory walletsStr = vm.envOr("WHITELISTED_WALLETS", string(""));
        if (bytes(walletsStr).length > 0) {
            // Parse comma-separated addresses
            // Note: Foundry's envOr doesn't natively split strings, so we use a simple approach
            // For production, pass wallets individually or use a separate config script
            address wallet = vm.envOr("ADMIN_ADDRESS", address(0));
            if (wallet != address(0)) {
                accessGate.addWallet(wallet);
                console.log("Wallet whitelisted:", wallet);
            }
        } else {
            // Default: whitelist the admin
            address admin = vm.envAddress("ADMIN_ADDRESS");
            accessGate.addWallet(admin);
            console.log("Admin wallet whitelisted:", admin);
        }
    }

    function _configureTradeLimits() internal {
        uint256 maxTradeSize = vm.envOr("MAX_TRADE_SIZE", uint256(0));
        uint256 maxDailyVolume = vm.envOr("MAX_DAILY_VOLUME", uint256(0));
        uint256 maxOpenPositions = vm.envOr("MAX_OPEN_POSITIONS", uint256(0));

        if (maxTradeSize > 0) tradeLimits.setMaxTradeSize(maxTradeSize);
        if (maxDailyVolume > 0) tradeLimits.setMaxDailyVolume(maxDailyVolume);
        if (maxOpenPositions > 0) tradeLimits.setMaxOpenPositions(maxOpenPositions);
    }

    function _createInstruments() internal {
        // wstETH/ETH — LST carry trade on Aave V3
        Symbol wstethEth = Symbol.wrap("wstETH/ETH");
        contango.createInstrument(wstethEth, WSTETH, IERC20(address(WETH)));

        // syrupUSDC/USDC — Stablecoin yield on Morpho Blue
        // Note: syrupUSDC address must be configured per deployment
        // Symbol syrupUsdc = Symbol.wrap("syrupUSDC/USDC");
        // contango.createInstrument(syrupUsdc, SYRUP_USDC, USDC);

        console.log("Instrument created: wstETH/ETH");
    }

}
