# Contango V2 Fork — Private Leverage Protocol

Fork of [contango-xyz/core-v2](https://github.com/contango-xyz/core-v2) stripped to essentials for private, fee-free leveraged yield farming on Aave V3 and Morpho Blue.

## How It Works

The protocol creates leveraged carry trades on yield-bearing tokens:

1. User deposits collateral (e.g., ETH) into the Vault
2. Contango takes a flash loan of the quote asset
3. Swaps quote → base on a whitelisted DEX (via KyberSwap)
4. Lends base (e.g., wstETH) as collateral on the money market
5. Borrows quote (e.g., ETH) to repay the flash loan
6. Net result: leveraged exposure to the yield spread (staking yield − borrow cost)

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Install dependencies
forge install

# Copy and configure environment
cp .env.example .env
# Edit .env with your RPC URLs, deployer key, admin address

# Build
FOUNDRY_PROFILE=dev forge build

# Run unit tests (no RPC needed)
FOUNDRY_PROFILE=dev forge test --match-path "test/unit/*"

# Run integration tests (requires MAINNET_URL in .env)
source .env
FOUNDRY_PROFILE=dev forge test --match-path "test/integration/*"

# Format
forge fmt
```

## Deploy

### Sepolia Testnet

```bash
source .env
forge script script/DeploySepolia.s.sol:DeploySepolia \
  --rpc-url $SEPOLIA_URL --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_MAINNET_KEY
```

### Mainnet

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MAINNET_URL --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_MAINNET_KEY
```

### Local Fork (for testing)

```bash
# Terminal 1: start Anvil fork
anvil --fork-url $MAINNET_URL

# Terminal 2: deploy
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

## Post-Deployment Admin

```bash
# Add a wallet to whitelist
forge script script/ConfigureWhitelist.s.sol:AddWallet \
  --rpc-url $RPC_URL --broadcast \
  --sig "run(address,address)" $ACCESS_GATE $WALLET

# Add a DEX router
forge script script/ConfigureWhitelist.s.sol:AddRouter \
  --rpc-url $RPC_URL --broadcast \
  --sig "run(address,address)" $ROUTER_GUARD $ROUTER

# Add a flash loan provider
forge script script/ConfigureWhitelist.s.sol:AddFlashLoanProvider \
  --rpc-url $RPC_URL --broadcast \
  --sig "run(address,address)" $ROUTER_GUARD $PROVIDER
```

## Architecture

```
Maestro (user entry: deposit/withdraw/trade)
  └── Contango (trade engine: flash loan → swap → lend/borrow)
        ├── AccessGate (wallet whitelist)
        ├── TradeLimits (per-trade size, daily volume, position count)
        ├── SpotExecutor → RouterGuard (DEX router whitelist)
        ├── Vault (token escrow, per-user balances)
        ├── PositionNFT (position ownership)
        └── UnderlyingPositionFactory
              ├── AaveMoneyMarket (Aave V3)
              └── MorphoBlueMoneyMarket (Morpho Blue)
```

## Security Model

| Layer | Contract | What it does |
|-------|----------|-------------|
| Wallet whitelist | `AccessGate` | Only whitelisted addresses (max 10) can trade |
| DEX whitelist | `RouterGuard` | Only whitelisted routers/spenders can execute swaps |
| Flash loan whitelist | `RouterGuard` | Only whitelisted providers can issue flash loans |
| Trade limits | `TradeLimits` | Per-trade size cap, daily volume cap, max open positions |
| Pause | `Contango` | Emergency pause halts all trading |
| Non-upgradeable | All | No proxy, no admin upgrade path — immutable deployment |

## DEX Integration (KyberSwap)

Swaps are executed via KyberSwap's MetaAggregationRouterV2. The off-chain helper builds the calldata:

```bash
npx ts-node script/kyberswap/quote.ts \
  --chain ethereum \
  --tokenIn 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 \
  --tokenOut 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0 \
  --amountIn 1000000000000000000 \
  --sender $CONTANGO_ADDRESS
```

Output is a JSON `ExecutionParams` object to pass to `Maestro.trade()`.

## Target Pairs

| Pair | Money Market | Strategy |
|------|-------------|----------|
| wstETH / ETH | Aave V3 (e-mode) | LST carry trade (~1-3% APR spread) |
| syrupUSDC / USDC | Morpho Blue | Stablecoin yield (~3-8% APR spread) |

## Tests

| Type | Count | Command |
|------|-------|---------|
| Unit | 327 | `FOUNDRY_PROFILE=dev forge test --match-path "test/unit/*"` |
| Integration (fork) | 12 | `FOUNDRY_PROFILE=dev forge test --match-path "test/integration/*"` |
| **Total** | **339** | `FOUNDRY_PROFILE=dev forge test` |

## Project Tracking

- `STATUS_REPORT.md` — Comprehensive development state and phase tracking
- `FORK_ROADMAP.md` — Original analysis and architecture decisions
- `CLAUDE.md` — AI assistant context for this codebase

## License

Upstream code: [BSL 1.1](https://github.com/contango-xyz/core-v2/blob/master/LICENSE.md) — production use allowed after 2027-09-01 or with grant from Contango Protocol Ltd. New security contracts and scripts in this fork follow the same license.
