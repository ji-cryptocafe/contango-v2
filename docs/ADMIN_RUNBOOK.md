# Admin Runbook

All admin operations require the deployer/owner private key.

## Wallet Management (AccessGate)

```bash
# Add a wallet
cast send $ACCESS_GATE "addWallet(address)" $WALLET \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Remove a wallet
cast send $ACCESS_GATE "removeWallet(address)" $WALLET \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Check if wallet is whitelisted
cast call $ACCESS_GATE "isWhitelisted(address)(bool)" $WALLET --rpc-url $RPC_URL

# Check current count and max
cast call $ACCESS_GATE "whitelistedCount()(uint256)" --rpc-url $RPC_URL
cast call $ACCESS_GATE "maxWhitelistedWallets()(uint256)" --rpc-url $RPC_URL

# Change max wallets
cast send $ACCESS_GATE "setMaxWhitelistedWallets(uint256)" 20 \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY
```

## Router Management (RouterGuard)

```bash
# Whitelist a DEX router (e.g., KyberSwap)
cast send $ROUTER_GUARD "setRouter(address,bool)" $ROUTER true \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY
cast send $ROUTER_GUARD "setSpender(address,bool)" $ROUTER true \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Remove a router
cast send $ROUTER_GUARD "setRouter(address,bool)" $ROUTER false \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY
cast send $ROUTER_GUARD "setSpender(address,bool)" $ROUTER false \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Whitelist a flash loan provider
cast send $ROUTER_GUARD "setFlashLoanProvider(address,bool)" $PROVIDER true \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Check status
cast call $ROUTER_GUARD "allowedRouters(address)(bool)" $ROUTER --rpc-url $RPC_URL
cast call $ROUTER_GUARD "allowedSpenders(address)(bool)" $SPENDER --rpc-url $RPC_URL
cast call $ROUTER_GUARD "allowedFlashLoanProviders(address)(bool)" $PROVIDER --rpc-url $RPC_URL
```

## Trade Limits (TradeLimits)

```bash
# Set max trade size (in base token units, 0 = unlimited)
cast send $TRADE_LIMITS "setMaxTradeSize(uint256)" 100000000000000000000 \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY  # 100 ETH

# Set max daily volume per user (0 = unlimited)
cast send $TRADE_LIMITS "setMaxDailyVolume(uint256)" 500000000000000000000 \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY  # 500 ETH

# Set max open positions per user (0 = unlimited)
cast send $TRADE_LIMITS "setMaxOpenPositions(uint256)" 5 \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Check limits
cast call $TRADE_LIMITS "maxTradeSize()(uint256)" --rpc-url $RPC_URL
cast call $TRADE_LIMITS "maxDailyVolume()(uint256)" --rpc-url $RPC_URL
cast call $TRADE_LIMITS "maxOpenPositions()(uint256)" --rpc-url $RPC_URL

# Check user state
cast call $TRADE_LIMITS "dailyVolume(address)(uint256)" $USER --rpc-url $RPC_URL
cast call $TRADE_LIMITS "openPositionCount(address)(uint256)" $USER --rpc-url $RPC_URL
```

## Emergency Operations (Contango)

```bash
# Pause all trading (requires EMERGENCY_BREAK_ROLE)
cast send $CONTANGO "pause()" --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Unpause (requires RESTARTER_ROLE)
cast send $CONTANGO "unpause()" --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Grant emergency roles (requires DEFAULT_ADMIN_ROLE)
cast send $CONTANGO "grantRole(bytes32,address)" \
  $(cast keccak "EMERGENCY_BREAK") $OPERATOR \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

cast send $CONTANGO "grantRole(bytes32,address)" \
  $(cast keccak "RESTARTER") $OPERATOR \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY
```

## Instrument Management

```bash
# Create a new trading pair (requires OPERATOR_ROLE on Contango)
# Symbol is bytes16, e.g., "wstETH/ETH" padded to 16 bytes
cast send $CONTANGO "createInstrument(bytes16,address,address)" \
  $(cast --format-bytes32 "wstETH/ETH" | cut -c1-34) \
  $WSTETH_ADDRESS $WETH_ADDRESS \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Set closing-only mode (no new positions, only close existing)
cast send $CONTANGO "setClosingOnly(bytes16,bool)" \
  $(cast --format-bytes32 "wstETH/ETH" | cut -c1-34) true \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Query instrument
cast call $CONTANGO "instrument(bytes16)" \
  $(cast --format-bytes32 "wstETH/ETH" | cut -c1-34) \
  --rpc-url $RPC_URL
```

## Token Support (Vault)

```bash
# Enable a token for vault deposits (requires OPERATOR_ROLE on Vault)
cast send $VAULT "setTokenSupport(address,bool)" $TOKEN true \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Check if token is supported
cast call $VAULT "isTokenSupported(address)(bool)" $TOKEN --rpc-url $RPC_URL

# Check balances
cast call $VAULT "balanceOf(address,address)(uint256)" $TOKEN $USER --rpc-url $RPC_URL
cast call $VAULT "totalBalanceOf(address)(uint256)" $TOKEN --rpc-url $RPC_URL
```

## Monitoring

### Events to Watch

```bash
# Position opened/closed/modified
cast logs --address $CONTANGO "PositionUpserted(bytes32,address,address,uint8,int256,int256,uint256,uint256,uint8)" \
  --rpc-url $RPC_URL --from-block latest

# Vault deposits/withdrawals
cast logs --address $VAULT "Deposited(address,address,uint256)" --rpc-url $RPC_URL --from-block latest
cast logs --address $VAULT "Withdrawn(address,address,uint256,address)" --rpc-url $RPC_URL --from-block latest

# Whitelist changes
cast logs --address $ACCESS_GATE "WalletWhitelisted(address)" --rpc-url $RPC_URL --from-block latest
cast logs --address $ACCESS_GATE "WalletRemoved(address)" --rpc-url $RPC_URL --from-block latest
```

### Health Checks

```bash
# Check if Contango is paused
cast call $CONTANGO "paused()(bool)" --rpc-url $RPC_URL

# Check position NFT exists
cast call $POSITION_NFT "exists(bytes32)(bool)" $POSITION_ID --rpc-url $RPC_URL

# Check position owner
cast call $POSITION_NFT "positionOwner(bytes32)(address)" $POSITION_ID --rpc-url $RPC_URL
```

## Opening a Position (Full Flow)

```bash
# 1. Approve WETH to Vault
cast send $WETH "approve(address,uint256)" $VAULT $(cast max-uint) \
  --rpc-url $RPC_URL --private-key $TRADER_KEY

# 2. Deposit via Maestro
cast send $MAESTRO "deposit(address,uint256)" $WETH $AMOUNT \
  --rpc-url $RPC_URL --private-key $TRADER_KEY

# Or deposit native ETH
cast send $MAESTRO "depositNative()" --value 1ether \
  --rpc-url $RPC_URL --private-key $TRADER_KEY

# 3. Get swap quote from KyberSwap
npx ts-node script/kyberswap/quote.ts \
  --chain ethereum \
  --tokenIn $WETH --tokenOut $WSTETH \
  --amountIn $SWAP_AMOUNT --sender $CONTANGO

# 4. Call trade with ExecutionParams from step 3
# Build the calldata manually or via a helper script
# TradeParams: positionId (symbol+mm+expiry, number=0 for new), quantity, limitPrice, cashflowCcy, cashflow
# ExecutionParams: router, spender, swapAmount, swapBytes, flashLoanProvider
```

## Closing a Position

```bash
# Use negative quantity to close
# quantity = -collateralBalance for full close
# cashflowCcy = Currency.Quote (2) to receive quote token
# cashflow = 0 for no additional cashflow
# Get swap quote (reverse direction) and call trade
```

## Ownership Transfer

All security contracts (AccessGate, RouterGuard, TradeLimits) use OpenZeppelin Ownable. To transfer ownership:

```bash
cast send $CONTRACT "transferOwnership(address)" $NEW_OWNER \
  --rpc-url $RPC_URL --private-key $CURRENT_OWNER_KEY
```

Contango and Vault use AccessControl. To transfer admin:

```bash
# Grant new admin
cast send $CONTANGO "grantRole(bytes32,address)" 0x0 $NEW_ADMIN \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Revoke old admin (careful — do this last)
cast send $CONTANGO "revokeRole(bytes32,address)" 0x0 $OLD_ADMIN \
  --rpc-url $RPC_URL --private-key $ADMIN_KEY
```
