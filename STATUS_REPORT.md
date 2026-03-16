# STATUS_REPORT.md

**Project:** Contango V2 Fork — Private, fee-free leverage protocol
**Last Updated:** 2026-03-16
**Current Phase:** Phase 2 Security Hardening (2.1-2.3 DONE, 2.4 next)
**Branch:** `fork/stripped`

---

## Overall Progress

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 0: Setup & Baseline | DONE | Foundry installed, build verified, branch `fork/stripped` created |
| Phase 1: Strip Non-Essential Code | DONE | 86 source files deleted, 3 modified, 52 test files deleted, 36 test files patched |
| Phase 4: Simplified Maestro | DONE | 341 → 80 lines. Removed orders, fees, routing, permit2, UUPS, swap helpers |
| Phase 5: Testing (Unit) | DONE | 303 tests across 15 suites in 9 files, all passing |
| Phase 2.1: AccessGate | DONE | Wallet whitelist (max 10), integrated into Contango.tradeOnBehalfOf() |
| Phase 2.2: RouterGuard | DONE | DEX router/spender/flash provider whitelist, integrated into SpotExecutors |
| Phase 2.3: Remove Upgradeability | DONE | Contango + Vault converted to non-upgradeable, no proxies |
| Phase 2.4: Trade Limits | NOT STARTED | Per-tx max size, daily volume, max positions |
| Phase 3: KyberSwap Integration | NOT STARTED | Off-chain pipeline + on-chain RouterGuard |
| Phase 5: Testing (Integration) | NOT STARTED | Fork tests for Aave wstETH/ETH, Morpho syrupUSDC/USDC |
| Phase 5: Testing (Security) | NOT STARTED | Tests for AccessGate, RouterGuard, trade limits |
| Phase 5: Testing (Invariant) | NOT STARTED | Vault accounting, position ownership invariants |
| Phase 6: Deployment Scripts | NOT STARTED | Foundry deploy scripts, configuration |
| Phase 7: Documentation & Ops | NOT STARTED | Admin runbook, monitoring |

---

## Codebase Metrics (Current State)

| Metric | Value |
|--------|-------|
| Source files (non-dependency) | 27 |
| Source files (with dependencies) | 53 |
| Total source lines | 4,896 |
| Maestro.sol lines | 80 |
| Unit test files | 8 |
| Unit test suites | 13 |
| Unit tests passing | 254 |
| Unit tests failing | 0 |
| Reduction from upstream | 86 source files deleted (~72%) |

---

## Phase 0: Setup & Baseline — DONE

- [x] Installed Foundry (forge 1.5.1-stable)
- [x] `FOUNDRY_PROFILE=dev forge build` compiles clean (warnings only, no errors)
- [x] Default profile (`forge build`) fails due to `deny_warnings=true` + code size warnings — expected, use `dev` profile for development
- [x] Created branch `fork/stripped` from `main`
- [ ] `.env` with RPC URLs — needed for integration tests (Phase 5.3)

---

## Phase 1: Strip Non-Essential Code — DONE

### Source Deletions (86 files)

**Directories deleted entirely:**
- [x] `src/strategies/` — StrategyBuilder, StrategyBlocks, PositionPermit
- [x] `src/token/` — ContangoToken, ContangoPerpetualOption, SmartWalletChecker
- [x] `src/periphery/` — LastOwnerBugFix
- [x] `src/moneymarkets/comet/` — Compound V3
- [x] `src/moneymarkets/compound/` — Compound V2 + Lodestar/Moonwell/Sonne
- [x] `src/moneymarkets/dolomite/`
- [x] `src/moneymarkets/euler/`
- [x] `src/moneymarkets/exactly/`
- [x] `src/moneymarkets/fluid/`
- [x] `src/moneymarkets/silo/`
- [x] `sdk/` — CLI tooling

**Individual files deleted:**
- [x] `src/core/OrderManager.sol`, `OrderManagerArbitrum.sol`, `OrderManagerOptimism.sol`
- [x] `src/interfaces/IOrderManager.sol`, `IFeeManager.sol`, `IFeeModel.sol`, `IReferralManager.sol`, `IContangoOracle.sol`
- [x] `src/moneymarkets/Liquidations.sol`, `BaseMoneyMarketView.sol`, `ContangoLens.sol`, `UpgradeableBeaconWithOwner.sol`
- [x] `src/moneymarkets/interfaces/IMoneyMarketView.sol`, `IContangoLens.sol`
- [x] `src/moneymarkets/aave/AaveV2MoneyMarket.sol`, `AaveV2MoneyMarketView.sol`, `AaveMoneyMarketView.sol`
- [x] `src/moneymarkets/morpho/MorphoBlueMoneyMarketView.sol`
- [x] `src/utils/Router.sol`, `TaxMan.sol`
- [x] `src/dependencies/Chainlink.sol`, `ArbGasInfo.sol`, `GasPriceOracle.sol`, `IPauseable.sol`, `Solidly.sol`, `DIAOracleV2.sol`

**Note:** `MorphoBlueReverseLookup.sol` was initially deleted but restored — it's required by `MorphoBlueMoneyMarket.sol` for payload→marketId mapping.

### Source Modifications (3 files)

| File | Changes |
|------|---------|
| `src/core/Maestro.sol` | Complete rewrite: 341→80 lines. Removed orders, fees, routing, permit2, UUPS, swap helpers. Constructor now `(IContango, IVault, SimpleSpotExecutor)`. |
| `src/interfaces/IMaestro.sol` | Stripped to deposit/withdraw/trade. Removed LinkedOrderParams, FeeCollected, SwapData convenience functions, routing, permit functions. No longer extends IOrderManagerErrors. |
| `src/moneymarkets/aave/dependencies/IAaveRewardsController.sol` | Inlined minimal `IAggregatorV2V3` interface (was imported from deleted `Chainlink.sol`) |

### Test Deletions (52 files)

- [x] `test/strategies/`, `test/token/`, `test/periphery/`, `test/flp/`
- [x] `test/moneymarkets/` for comet, compound, dolomite, euler, exactly, fluid, silo
- [x] `test/core/functional/OrderManager.ft.t.sol`

### Test Modifications (36 files)

Major test files patched to compile after source deletions:
- `test/TestSetup.t.sol` (~83K) — removed imports for all deleted MMs, stripped deployment functions, updated Maestro constructor
- `test/TSQuoter.sol` — removed ContangoLens dependency, added local struct definitions
- `test/Importer.sol` — removed ExactlyPreviewer, ChainlinkAggregator imports
- `test/PositionActions.sol` — removed depositWithPermit path
- `test/core/Maestro.t.sol` — removed tests for deleted features
- `test/core/functional/Upgrades.t.sol` — removed ContangoLens/OrderManager/StrategyBuilder upgrade tests
- `test/core/functional/PositionLifeCycle.ft.t.sol` — removed test contracts for deleted MMs
- `test/moneymarkets/aave/*.t.sol` — replaced AaveMoneyMarketView references
- Multiple files stubbed out (referenced entirely deleted source)

### Remaining Source Files (27 non-dependency)

```
src/core/
├── Contango.sol              # Trade engine (745 lines, unchanged)
├── Maestro.sol               # Simplified entry point (80 lines, rewritten)
├── PositionNFT.sol           # Position ownership NFT (63 lines, unchanged)
└── Vault.sol                 # Token escrow (147 lines, unchanged)

src/interfaces/
├── IContango.sol             # Trade types + events (143 lines)
├── IMaestro.sol              # Simplified interface (47 lines, rewritten)
└── IVault.sol                # Vault interface (47 lines)

src/libraries/
├── Arrays.sol                # Array helpers
├── BitFlags.sol              # Bit manipulation
├── DataTypes.sol             # Core types (PositionId, Symbol, MoneyMarketId, etc.)
├── ERC20Lib.sol              # Token transfer utilities
├── Errors.sol                # Shared errors
├── extensions/PositionIdExt.sol  # PositionId encoding/decoding
├── MathLib.sol               # absIfPositive/absIfNegative
├── Roles.sol                 # Access control role constants
└── Validations.sol           # Position permission checks

src/moneymarkets/
├── BaseMoneyMarket.sol       # Abstract base for all MM adapters
├── ImmutableBeaconProxy.sol  # Proxy helper for cloned MMs
├── UnderlyingPositionFactory.sol  # Creates/manages MM instances per position
├── interfaces/
│   ├── IFlashBorrowProvider.sol   # Flash borrow interface (Aave)
│   ├── IMoneyMarket.sol           # Core MM interface
│   └── IUnderlyingPositionFactory.sol
├── aave/
│   └── AaveMoneyMarket.sol   # Aave V3 adapter (+ 16 dependency interfaces)
└── morpho/
    ├── MorphoBlueMoneyMarket.sol      # Morpho Blue adapter
    └── MorphoBlueReverseLookup.sol    # Payload→MarketId lookup

src/utils/
├── SpotExecutor.sol          # DEX swap for Contango (37 lines)
└── SimpleSpotExecutor.sol    # DEX swap for Maestro (40 lines)

src/dependencies/
├── IWETH9.sol, PayableMulticall.sol, Rewards.sol, Uniswap.sol
```

---

## Phase 4: Simplified Maestro — DONE

Maestro reduced from 341 lines to 80 lines. Final public API:

```solidity
contract Maestro is IMaestro, PayableMulticall {
    IContango public immutable contango;
    IVault public immutable vault;
    PositionNFT public immutable positionNFT;
    IWETH9 public immutable nativeToken;
    SimpleSpotExecutor public immutable spotExecutor;

    constructor(IContango _contango, IVault _vault, SimpleSpotExecutor _spotExecutor);

    function deposit(IERC20 token, uint256 amount) public payable returns (uint256);
    function depositNative() public payable returns (uint256);
    function withdraw(IERC20 token, uint256 amount, address to) public payable returns (uint256);
    function withdrawNative(uint256 amount, address to) public payable returns (uint256);
    function trade(TradeParams memory tradeParams, ExecutionParams calldata execParams)
        public payable returns (PositionId, Trade memory);
}
```

**Removed:**
- `IOrderManager orderManager`, `IPermit2 permit2`, `Router router`, `address treasury`, `Timelock timelock`
- All `tradeAndLinkedOrder*`, `placeLinkedOrder`, `cancel` functions
- `tradeWithFees`, `FeeParams`, `FeeCollected` event
- `depositWithPermit`, `depositWithPermit2`
- `swapAndDeposit*`, `swapAndWithdraw*`
- `route()`, `isIntegration()`, `setIntegration()`, `transferPosition()`
- `UUPSUpgradeable`, `_authorizeUpgrade()`, `onlyTimelock` modifier

---

## Phase 5: Testing (Unit) — DONE

**254 tests, 13 suites, 8 files. All passing.**

Run with: `FOUNDRY_PROFILE=dev forge test --match-path "test/unit/*" -v`

### Test File Breakdown

| File | Suites | Tests | Coverage Focus |
|------|--------|-------|----------------|
| `test/unit/Vault.t.sol` | VaultUnitTest | 48 | deposit, withdraw, native, auth, pre-funded deposit, accounting, edge cases |
| `test/unit/PositionNFT.t.sol` | PositionNFTTest | 45 | mint, burn, ownership, approvals, contangoContracts, ERC721 transfers, supportsInterface |
| `test/unit/PositionIdExt.t.sol` | PositionIdExtTest | 41 | encode/decode, getSymbol/Number/MM/Expiry, isPerp, isExpired, withNumber, flags, payload, fuzz round-trip |
| `test/unit/BaseMoneyMarket.t.sol` | BaseMoneyMarketTest | 28 | onlyContango guard (all 6 functions), initialise, lend/withdraw/borrow/repay (zero+normal), retrieve, supportsInterface |
| `test/unit/Maestro.t.sol` | MaestroUnitTest | 21 | deposit, withdraw (ALL=0), trade permissions, cashflow max, receive, multicall |
| `test/unit/UnderlyingPositionFactory.t.sol` | UnderlyingPositionFactoryTest | 17 | register, double-register revert, clone vs direct, access control, multiple MMs |
| `test/unit/Libraries.t.sol` | MathLibTest | 14 | absIfPositive/absIfNegative, edge cases (min/max int256), fuzz |
| | ArraysTest | 9 | toArray/toStringArray for uint256, address, bytes, string |
| | BitFlagsTest | 7 | isBitSet (bits 0-7, all/none, revert >7) |
| | DataTypesTest | 7 | payloadEquals, mmEquals (equal, unequal, zero, max) |
| | ValidationsTest | 6 | validateCreate/Modify permissions (owner, approved, unauthorized) |
| `test/unit/SpotExecutor.t.sol` | SpotExecutorTest | 5 | swap base/quote input, price calculation, approve flow, calldata forwarding |
| | SimpleSpotExecutorTest | 6 | swap, minAmountOut enforcement, zero min, event, arbitrary calldata |
| **Total** | **13** | **254** | |

### Test Patterns Used

- **Mock contracts**: MockERC20, MockWETH9, MockRouter, MockMoneyMarket, MockContango, MockVault, MockPositionNFT
- **Wrapper contracts**: `PositionIdCaller`, `BitFlagsCaller`, `ValidationsCaller` — needed because `vm.expectRevert` only works with external calls, not free functions
- **OZ v4 access control**: Tests use string-based revert messages (`"AccessControl: account 0x... is missing role 0x..."`) not OZ v5 custom errors
- **Fuzz tests**: PositionId round-trip, MathLib abs functions, AccessControl with random addresses

---

## Phase 2: Security Hardening — NOT STARTED

### Step 2.1 — AccessGate (Wallet Whitelist)

| Task | Status |
|------|--------|
| Create `src/security/AccessGate.sol` | NOT STARTED |
| Integrate into `Contango.sol` — `onlyWhitelisted` on `trade()`, `tradeOnBehalfOf()` | NOT STARTED |
| Integrate into `Maestro.sol` — whitelist check on `deposit()`, `withdraw()`, `trade()` | NOT STARTED |
| Restrict `PositionNFT` transfers to whitelisted addresses | NOT STARTED |
| Hard cap: 10 whitelisted wallets | NOT STARTED |
| Write tests first (TDD): `test/unit/AccessGate.t.sol` | NOT STARTED |

### Step 2.2 — RouterGuard (DEX Router Whitelist) — HIGHEST PRIORITY

**Critical vulnerability:** `SpotExecutor.sol:25-26` and `SimpleSpotExecutor.sol:30-31` accept arbitrary `router` and `spender` from calldata. A malicious caller can drain tokens.

| Task | Status |
|------|--------|
| Write tests first (TDD): `test/unit/RouterGuard.t.sol` | NOT STARTED |
| Create `src/security/RouterGuard.sol` | NOT STARTED |
| Inject as immutable into `SpotExecutor` — validate before `Address.functionCall()` | NOT STARTED |
| Inject as immutable into `SimpleSpotExecutor` — validate before `Address.functionCall()` | NOT STARTED |
| Validate `flashLoanProvider` in `Contango._flash()` | NOT STARTED |
| Update `SpotExecutor.t.sol` — test guard integration | NOT STARTED |

### Step 2.3 — Remove Upgradeability

| Task | Status |
|------|--------|
| `Contango.sol` — replace `UUPSUpgradeable` with constructor, remove `__gap` | NOT STARTED |
| `Vault.sol` — replace upgradeable OZ with standard OZ, constructor init | NOT STARTED |
| Update `Vault.t.sol` — remove proxy deployment, use direct constructor | NOT STARTED |

**Note:** Maestro already had upgradeability removed in Phase 4.

### Step 2.4 — Additional Hardening

| Task | Status |
|------|--------|
| Add `nonReentrant` to `Contango.trade()` and `tradeOnBehalfOf()` | NOT STARTED |
| Add per-tx max trade size limit | NOT STARTED |
| Add per-epoch (daily) volume limit | NOT STARTED |
| Add max open positions per user | NOT STARTED |
| Write tests first (TDD): `test/unit/TradeLimits.t.sol` | NOT STARTED |

---

## Phase 3: KyberSwap Aggregator Integration — NOT STARTED

### Architecture

KyberSwap fits naturally into the existing `ExecutionParams` pattern:

```
Off-chain (before tx):
  1. Call KyberSwap GET /api/v1/routes → get routeSummary + routerAddress
  2. Call KyberSwap POST /api/v1/route/build → get encoded swapData (hex calldata)

On-chain (in tx):
  3. Pass to Contango via ExecutionParams:
     - execParams.router = KyberSwap MetaAggregationRouterV2 address
     - execParams.spender = same router address (or allowance target)
     - execParams.swapBytes = encoded swapData from API
     - execParams.swapAmount = amountIn from quote
     - execParams.flashLoanProvider = ERC7399 wrapper (Balancer/Aave)
  4. SpotExecutor.executeSwap() calls router with calldata
  5. RouterGuard validates router is whitelisted before execution
```

### KyberSwap API Details

| Item | Value |
|------|-------|
| API Base | `https://aggregator-api.kyberswap.com` |
| Get Route | `GET /{chain}/api/v1/routes?tokenIn=&tokenOut=&amountIn=` |
| Build Route | `POST /{chain}/api/v1/route/build` with `{routeSummary, sender, recipient, slippageTolerance}` |
| Router Contract | `MetaAggregationRouterV2` (address returned per-chain by API) |
| Auth | None required (no API key) |
| Chains | All major EVM chains |

### Implementation Tasks

| Task | Status |
|------|--------|
| **On-chain: RouterGuard whitelist** | |
| Add KyberSwap MetaAggregationRouterV2 to `RouterGuard.allowedRouters` | NOT STARTED |
| Add KyberSwap router to `RouterGuard.allowedSpenders` | NOT STARTED |
| Verify token approval flow (router as spender vs separate allowance target) | NOT STARTED |
| **Off-chain: Quote & Encode Pipeline** | |
| Create TypeScript helper to call KyberSwap GET route API | NOT STARTED |
| Create helper to call KyberSwap POST route/build API | NOT STARTED |
| Create helper to construct `ExecutionParams` from KyberSwap response | NOT STARTED |
| Create end-to-end script: quote → build → construct calldata → send tx | NOT STARTED |
| **Testing** | |
| Fork test: KyberSwap swap wstETH↔ETH via SpotExecutor (mainnet fork) | NOT STARTED |
| Fork test: KyberSwap swap syrupUSDC↔USDC via SpotExecutor (mainnet fork) | NOT STARTED |
| Test RouterGuard rejects non-KyberSwap router addresses | NOT STARTED |

### Why KyberSwap

- **No API key required** — simpler operational setup
- **Single API spec for all EVM chains** — consistent interface
- **MetaAggregationRouterV2** — single router contract, straightforward to whitelist
- **Fits existing pattern** — encoded calldata goes directly into `execParams.swapBytes`

### Alternative Aggregators (Backup)

| Aggregator | Notes |
|-----------|-------|
| 1inch | Requires API key; well-established |
| ParaSwap | Good for stablecoin swaps |
| 0x / Matcha | Requires API key |
| Uniswap Universal Router | Direct, no aggregator — worse pricing but no API dependency |

---

## Phase 5: Testing (Integration) — NOT STARTED

Requires `.env` with `MAINNET_URL` RPC endpoint.

### Fork Integration Tests

| Test | Chain | Pair | Money Market | Status |
|------|-------|------|-------------|--------|
| Open/close wstETH/ETH long | Mainnet | wstETH/ETH | Aave V3 (e-mode) | NOT STARTED |
| Open/close syrupUSDC/USDC long | Mainnet | syrupUSDC/USDC | Morpho Blue | NOT STARTED |
| Full lifecycle: deposit→open→modify→close→withdraw | Mainnet | wstETH/ETH | Aave V3 | NOT STARTED |
| KyberSwap routing via SpotExecutor | Mainnet | wstETH↔ETH | n/a | NOT STARTED |
| Leverage sweep: 2x, 3x, 5x positions | Mainnet | wstETH/ETH | Aave V3 | NOT STARTED |

### Security Integration Tests

| Test | Status |
|------|--------|
| Whitelisted user opens position, non-whitelisted reverts | NOT STARTED |
| Whitelisted router executes swap, non-whitelisted reverts | NOT STARTED |
| Position transfer restricted to whitelisted addresses | NOT STARTED |
| Trade size limits enforced | NOT STARTED |
| Daily volume limits enforced with epoch reset | NOT STARTED |

### Invariant Tests

| Test | Invariant | Status |
|------|-----------|--------|
| VaultInvariant | totalBalance == sum(accountBalances); balance >= totalBalance | NOT STARTED |
| PositionInvariant | only whitelisted addresses own positions; count <= max | NOT STARTED |

---

## Phase 6: Deployment Scripts — NOT STARTED

### Deployment Order

```
1.  PositionNFT
2.  Vault
3.  RouterGuard
4.  SpotExecutor (with RouterGuard)
5.  SimpleSpotExecutor (with RouterGuard)
6.  UnderlyingPositionFactory
7.  AaveMoneyMarket adapter
8.  MorphoBlueMoneyMarket adapter
9.  Register adapters in factory
10. Contango (with AccessGate, NFT, Vault, Factory, SpotExecutor)
11. Maestro (with Contango, Vault, SimpleSpotExecutor)
12. Grant roles: Contango → MINTER on NFT, CONTANGO on Vault + Factory
13. Whitelist wallets in AccessGate
14. Whitelist KyberSwap MetaAggregationRouterV2 in RouterGuard
15. Whitelist flash loan providers in RouterGuard
16. Create instruments (wstETH/ETH, syrupUSDC/USDC symbols)
```

| Task | Status |
|------|--------|
| `script/Deploy.s.sol` — full deployment sequence | NOT STARTED |
| `script/ConfigureWhitelist.s.sol` — add wallets to AccessGate | NOT STARTED |
| `script/ConfigureRouters.s.sol` — whitelist KyberSwap router | NOT STARTED |
| `script/CreateInstruments.s.sol` — register pairs | NOT STARTED |
| `.env.example` with required variables | NOT STARTED |

---

## Phase 7: Documentation & Ops — NOT STARTED

| Task | Status |
|------|--------|
| Update README.md for fork | NOT STARTED |
| Admin runbook: whitelist mgmt, pause/unpause, router updates | NOT STARTED |
| Position management guide: open/close via cast or script | NOT STARTED |
| Monitoring checklist: PositionUpserted events, health factors, volume | NOT STARTED |

---

## Target Pairs

| Pair | Money Market | Chain | Strategy | Expected Spread |
|------|-------------|-------|----------|-----------------|
| wstETH / ETH | Aave V3 (e-mode) | Mainnet | LST carry trade | ~1-3% APR |
| syrupUSDC / USDC | Morpho Blue | Mainnet | Stablecoin yield | ~3-8% APR |

Future candidates (post-initial deployment):
- rETH/ETH on Aave V3
- sDAI/DAI on Morpho Blue
- sUSDe/USDC on Morpho Blue (higher risk/reward)

---

## Critical Path (Updated)

```
Phase 0 (baseline) ✅
  → Phase 1 (strip code) ✅
    → Phase 4 (simplified Maestro) ✅
      → Phase 5 unit tests (TDD) ✅
        → Phase 2.2 (RouterGuard — HIGHEST PRIORITY) ← NEXT
          → Phase 2.1 (AccessGate)
            → Phase 2.3 (remove upgradeability)
              → Phase 2.4 (trade limits)
                → Phase 3 (KyberSwap integration)
                  → Phase 5 integration tests
                    → Phase 6 (deployment)
                      → Phase 7 (docs)
```

**Next action:** Write `test/unit/RouterGuard.t.sol` first (TDD), then implement `src/security/RouterGuard.sol`.

---

## Key Files Reference

| File | Role | Lines |
|------|------|-------|
| `src/core/Contango.sol` | Trade engine — flash loan orchestration | 745 |
| `src/core/Maestro.sol` | User entry point (simplified) | 80 |
| `src/core/Vault.sol` | Token escrow | 147 |
| `src/core/PositionNFT.sol` | Position ownership NFT | 63 |
| `src/utils/SpotExecutor.sol` | DEX swap for Contango (needs RouterGuard) | 37 |
| `src/utils/SimpleSpotExecutor.sol` | DEX swap for Maestro (needs RouterGuard) | 40 |
| `src/interfaces/IContango.sol` | ExecutionParams, Trade, TradeParams structs | 143 |
| `src/moneymarkets/aave/AaveMoneyMarket.sol` | Aave V3 adapter | ~200 |
| `src/moneymarkets/morpho/MorphoBlueMoneyMarket.sol` | Morpho Blue adapter | 128 |
| `src/moneymarkets/BaseMoneyMarket.sol` | Abstract base for MM adapters | 138 |
| `src/moneymarkets/UnderlyingPositionFactory.sol` | MM instance management | 64 |
| `src/libraries/DataTypes.sol` | PositionId, Symbol, MoneyMarketId types | 73 |
| `src/libraries/extensions/PositionIdExt.sol` | PositionId encoding/decoding | 80 |
| `FORK_ROADMAP.md` | Original analysis document | ~920 |
| `foundry.toml` | Build config, RPC endpoints, formatter | 199 |

---

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-15 | KyberSwap as primary DEX aggregator | No API key, single router contract per chain, fits ExecutionParams pattern |
| 2026-03-15 | Keep only Aave V3 + Morpho Blue | Covers LST carry (wstETH/ETH) and stablecoin yield (syrupUSDC/USDC) |
| 2026-03-15 | Remove upgradeability | Small user set, immutable = smaller attack surface |
| 2026-03-15 | Mainnet-first deployment | Both target money markets have deepest liquidity on mainnet |
| 2026-03-15 | TDD approach | Write tests before implementing security contracts (RouterGuard, AccessGate) |
| 2026-03-15 | Restore MorphoBlueReverseLookup | Initially deleted, but required by MorphoBlueMoneyMarket for payload→marketId mapping |
| 2026-03-15 | Maestro rewrite vs. modification | Full rewrite cleaner than incremental deletion — 341→80 lines, constructor simplified |

---

## Known Issues / Tech Debt

| Issue | Severity | Notes |
|-------|----------|-------|
| SpotExecutor accepts arbitrary router/spender | CRITICAL | Phase 2.2 (RouterGuard) is the fix. Attacker can drain tokens via malicious router calldata. |
| Contango/Vault still use UUPS upgradeability | MEDIUM | Phase 2.3 will remove. Admin key compromise = total protocol compromise. |
| No reentrancy guard on Contango.trade() | MEDIUM | Phase 2.4. Flash loan callbacks are external — defense-in-depth needed. |
| `FeeParams` struct still in DataTypes.sol | LOW | Unused after Maestro simplification. Can remove in cleanup pass. |
| `test/TestSetup.t.sol` is 83K with many stubs | LOW | Many test functions stubbed out after stripping. Clean up when integration tests are written. |
| Default forge profile fails (deny_warnings) | LOW | Use `FOUNDRY_PROFILE=dev` for development. Fix in foundry.toml if needed. |
