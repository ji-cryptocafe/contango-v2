# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Contango V2 fork — building a private, fee-free leverage protocol for yield-bearing tokens on top of existing money markets. When a trader opens a position, the protocol borrows from a money market, swaps on the spot market, then lends back on the same money market.

**Fork goal:** Strip to essentials (Aave V3 + Morpho Blue only), add extreme access control (wallet whitelist, router whitelist), remove all fee extraction. See `FORK_ROADMAP.md` for full analysis and `STATUS_REPORT.md` for current progress.

**License:** BUSL-1.1 (production use after 2027-09-01 or with grant from Contango Protocol Ltd.)

## Build & Test Commands

```bash
forge install          # Install dependencies
forge build            # Compile contracts
forge fmt              # Format code
forge test             # Run all tests (requires .env with RPC URLs)
forge test --match-test testFunctionName   # Run a single test by name
forge test --match-contract ContractName   # Run tests in a specific contract
forge test --match-path test/moneymarkets/aave/**  # Run tests matching a path
FOUNDRY_PROFILE=dev forge build  # Build without optimizer (faster, no code size checks)
```

**Environment**: Requires `.env` file with RPC URLs: `MAINNET_URL`, `ARBITRUM_URL`, `OPTIMISM_URL`, `POLYGON_URL`, `GNOSIS_URL`, `BASE_URL`, `BSC_URL`, `LINEA_URL`, `AVALANCHE_URL`, `SCROLL_URL`.

**Compiler**: Solidity 0.8.27, EVM target Cancun, optimizer 200 runs. `deny_warnings = true` in default profile.

## Formatting

Configured in `foundry.toml` under `[fmt]`: 140 char line length, 4-space tabs, double quotes, `attributes_first` multiline function headers, bracket spacing enabled, `long` int types (uint256 not uint).

## Architecture

### Core Flow

`Maestro` (user entry point) → `Contango` (position engine + flash loans) → Money Market adapters → External protocols

Positions are represented as NFTs (`PositionNFT`). Each position is identified by a `PositionId` (bytes32) that encodes: Symbol, position number, MoneyMarketId, expiry, and flags (see `PositionIdExt.sol`).

### Swap Execution Pattern

Swaps are executed via `SpotExecutor` using `ExecutionParams`:
- `execParams.router` — DEX router contract address (e.g., KyberSwap MetaAggregationRouterV2)
- `execParams.spender` — token approval target
- `execParams.swapBytes` — encoded calldata from aggregator API
- `execParams.swapAmount` — amount to swap
- `execParams.flashLoanProvider` — ERC7399 flash loan provider

**CRITICAL:** Currently no on-chain validation of router/spender addresses. RouterGuard is the highest priority security addition.

### Key Contracts

- **`Contango.sol`** — Main engine: creates/modifies/closes positions via flash loan callbacks
- **`Maestro.sol`** — User-facing wrapper with convenience methods (to be simplified)
- **`Vault.sol`** — Token custody for user balances
- **`PositionNFT.sol`** — NFT representation of positions
- **`SpotExecutor.sol`** / **`SimpleSpotExecutor.sol`** — DEX swap execution (needs RouterGuard)

### Money Market Integrations (src/moneymarkets/)

Each integration follows a consistent pattern:
- `*MoneyMarket.sol` — Implements lending/borrowing operations (extends `BaseMoneyMarket`)
- `*MoneyMarketView.sol` — Read-only queries for prices, rates, balances (extends `BaseMoneyMarketView`)

**Target adapters for fork:** Aave V3 (wstETH/ETH carry trade), Morpho Blue (syrupUSDC/USDC yield)

### Key Types (src/libraries/DataTypes.sol)

- `PositionId` (bytes32) — Encoded position identifier
- `Symbol` (bytes16) — Trading pair identifier
- `MoneyMarketId` (uint8) — Money market protocol identifier
- `Currency` enum — None/Base/Quote
- `ExecutionParams` struct — Router, spender, swapBytes, flashLoanProvider

### Access Control

Uses OpenZeppelin AccessControl with roles defined in `Roles.sol`: OPERATOR, CONTANGO, BOT, EMERGENCY_BREAK, RESTARTER, MINTER, BURNER, MODIFIER.

## Test Structure

Tests are in `test/` with suffixes indicating type:
- `*.t.sol` — Unit tests
- `*.ft.t.sol` — Functional tests (position lifecycle scenarios)
- `*.it.t.sol` — Integration tests (fork tests with real DEX data)
- `*.invariant.t.sol` — Invariant/fuzz tests

`test/TestSetup.t.sol` is the large shared test setup (~83K) with network configurations. Most money market tests require forking (they interact with live protocol state).

## Dependencies

Managed as git submodules in `lib/`. Key mappings in `remappings.txt`:
- `@openzeppelin/contracts/` — OpenZeppelin
- `erc7399/` — Flash loan standard (ERC-7399)
- `@prb/math/` — Fixed-point math
- `@contango/erc721Permit2/` — NFT permit2
- `solady/` — Gas-optimized utilities

## DEX Aggregator: KyberSwap

Primary aggregator for swap execution. Off-chain flow:
1. `GET /{chain}/api/v1/routes?tokenIn=&tokenOut=&amountIn=` → routeSummary + routerAddress
2. `POST /{chain}/api/v1/route/build` with `{routeSummary, sender, recipient, slippageTolerance}` → encoded swapData

On-chain: pass `routerAddress` as `execParams.router`, `swapData` as `execParams.swapBytes`.
