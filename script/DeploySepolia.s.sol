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

import "src/dependencies/IWETH9.sol";

/// @title DeploySepolia — Deploy to Sepolia testnet with Aave V3
/// @dev Usage:
///   source .env
///   forge script script/DeploySepolia.s.sol:DeploySepolia \
///     --rpc-url $SEPOLIA_URL \
///     --broadcast \
///     --verify \
///     --etherscan-api-key $ETHERSCAN_MAINNET_KEY
contract DeploySepolia is Script {

    // --- Sepolia addresses ---
    // https://docs.aave.com/developers/deployed-contracts/v3-testnet-addresses
    IWETH9 constant WETH = IWETH9(0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c); // Aave WETH on Sepolia
    IPoolAddressesProvider constant AAVE_ADDRESSES_PROVIDER =
        IPoolAddressesProvider(0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A);
    IAaveRewardsController constant AAVE_REWARDS =
        IAaveRewardsController(0x4DA5c4da71C5a167171cC839487536d86e083483);
    MoneyMarketId constant MM_AAVE = MoneyMarketId.wrap(1);

    // Aave testnet tokens (faucet: https://app.aave.com/faucet/)
    IERC20 constant AAVE_WETH = IERC20(0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c);
    IERC20 constant AAVE_USDC = IERC20(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8);

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        Timelock timelock = Timelock.wrap(admin);

        vm.startBroadcast(deployerKey);

        // 1. Security
        RouterGuard routerGuard = new RouterGuard();
        AccessGate accessGate = new AccessGate();
        TradeLimits tradeLimits = new TradeLimits();

        // 2. Core
        PositionNFT positionNFT = new PositionNFT(timelock);
        Vault vault = new Vault(WETH, timelock);
        UnderlyingPositionFactory positionFactory = new UnderlyingPositionFactory(timelock);

        // 3. Executors
        SpotExecutor spotExecutor = new SpotExecutor(routerGuard);
        SimpleSpotExecutor simpleSpotExecutor = new SimpleSpotExecutor(routerGuard);

        // 4. Contango
        Contango contango =
            new Contango(positionNFT, vault, positionFactory, spotExecutor, accessGate, tradeLimits, timelock);
        tradeLimits.setContango(address(contango));

        // 5. Maestro
        Maestro maestro = new Maestro(IContango(address(contango)), vault, simpleSpotExecutor);

        // 6. Roles
        vault.grantRole(OPERATOR_ROLE, admin);
        vault.grantRole(CONTANGO_ROLE, address(contango));
        vault.grantRole(CONTANGO_ROLE, address(maestro));
        positionNFT.grantRole(MINTER_ROLE, address(contango));
        positionNFT.setContangoContract(address(maestro), true);
        positionFactory.grantRole(CONTANGO_ROLE, address(contango));
        contango.grantRole(OPERATOR_ROLE, admin);

        // 7. Token support
        vault.setTokenSupport(AAVE_USDC, true);

        // 8. Aave V3
        AaveMoneyMarket aaveMM =
            new AaveMoneyMarket(MM_AAVE, IContango(address(contango)), AAVE_ADDRESSES_PROVIDER, AAVE_REWARDS, true);
        positionFactory.registerMoneyMarket(IMoneyMarket(address(aaveMM)));

        // 9. Whitelist admin wallet
        accessGate.addWallet(admin);

        // 10. Create test instrument (WETH/USDC as placeholder)
        contango.createInstrument(Symbol.wrap("WETH/USDC"), AAVE_WETH, AAVE_USDC);

        // 11. Transfer security contract ownership to admin
        routerGuard.transferOwnership(admin);
        accessGate.transferOwnership(admin);
        tradeLimits.transferOwnership(admin);

        vm.stopBroadcast();

        console.log("=== Sepolia Deployment ===");
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
        console.log("AaveMoneyMarket:   ", address(aaveMM));
        console.log("");
        console.log("Next steps:");
        console.log("1. Whitelist a DEX router:  cast send", address(routerGuard), "'setRouter(address,bool)' <ROUTER> true");
        console.log("2. Get testnet tokens: https://app.aave.com/faucet/");
        console.log("3. Approve + deposit via Maestro, then trade");
    }

}
