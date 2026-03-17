# Security Audit Report — Contango V2 Fork

**Auditor:** Claude (AI Security Audit)
**Date:** 2026-03-17
**Scope:** Full codebase — core engine, money market adapters, security contracts, libraries
**Methodology:** Manual review with attacker mindset, covering OWASP smart contract top 10, flash loan vectors, access control, oracle manipulation, and protocol-specific attack patterns.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Audit Journey](#audit-journey)
3. [Critical Findings](#critical-findings)
4. [High Severity Findings](#high-severity-findings)
5. [Medium Severity Findings](#medium-severity-findings)
6. [Low Severity Findings](#low-severity-findings)
7. [Informational / Design Notes](#informational)
8. [Architecture Strengths](#architecture-strengths)
9. [Recommendations Summary](#recommendations)

---

## Executive Summary

The Contango V2 fork implements a leveraged position protocol built on top of Aave V3 and Morpho Blue money markets. The fork adds significant security hardening (AccessGate, RouterGuard, TradeLimits) beyond the original Contango codebase.

**Overall Assessment:** The codebase is well-architected with proper separation of concerns. The most critical risks are concentrated in three areas:
1. **PayableMulticall + flash loan callback interaction** — the most sophisticated attack surface
2. **TradeLimits/AccessGate missing access control** — anyone can call these externally
3. **Lack of reentrancy guards on Contango callbacks** — relies on hash-based checks only

| Severity | Count |
|----------|-------|
| Critical | 3 |
| High     | 4 |
| Medium   | 7 |
| Low      | 5 |
| Info     | 4 |

---

## Audit Journey

### Phase 1: Standard Vulnerability Classes

#### 1.1 Integer Overflow/Underflow

Solidity 0.8.27 provides built-in overflow protection. Checked all `unchecked` blocks:

- **`MathLib.sol:11-12`** — `unchecked { return value < 0 ? uint256(-value) : 0; }` — **SAFE**. The conditional guards against negating `type(int256).min`.
- **`Contango.sol:127`** — `uint256(-tradeParams.quantity)` — **SAFE** when `quantity < 0` (guarded by else-if).
- **`PayableMulticall.sol:21`** — loop index `i++` — **SAFE** (standard pattern, bounded by array length).

**Verdict:** No integer overflow vulnerabilities found. The codebase correctly avoids `unchecked` in business logic.

#### 1.2 Oracle Manipulation

Neither adapter directly calls oracles. Both delegate oracle responsibility to the underlying protocol:
- **Aave V3:** Pool internally reads `IAaveOracle` for health factor calculations
- **Morpho Blue:** Uses `IMorphoOracle.price()` for collateralization checks

**Risk:** If underlying oracle is manipulated (e.g., Chainlink lag, Uniswap TWAP manipulation), positions could be opened at inflated collateral values or liquidated unfairly. However, this is **inherited risk** from the money market, not a Contango-specific vulnerability.

**Verdict:** No direct oracle attack surface. Protocol inherits money market oracle risks.

#### 1.3 Access Control

Reviewed every `external`/`public` function for proper authorization.

#### 1.4 Flash Loan Attacks

Detailed below in Critical and High findings.

---

### Phase 2: Protocol-Specific Attack Vectors

Focused on the unique aspects of this protocol:
- Flash loan callback verification mechanism
- Position NFT permission model
- Vault deposit/withdrawal accounting
- Multicall + delegatecall interaction
- Router/spender trust model
- Money market adapter fund flows

---

### Phase 3: Complex/Compositional Attacks

Looked for multi-step attack chains:
- Multicall batching to manipulate state between steps
- Flash loan + callback hash collision
- Cross-function reentrancy via ERC-777 or hook tokens
- Governance/admin key compromise scenarios

---

## Critical Findings

### C-01: TradeLimits and AccessGate Lack Access Control on State-Mutating Functions

**Severity:** CRITICAL
**Files:** `src/security/TradeLimits.sol:50,69,76` | `src/security/AccessGate.sol:47`

**Description:**

`TradeLimits.recordAndValidateVolume()`, `incrementOpenPositions()`, and `decrementOpenPositions()` are `external` functions with **no access control**. Anyone can call them.

```solidity
// TradeLimits.sol:50 — no modifier, no caller check
function recordAndValidateVolume(address trader, uint256 volume) external {
    ...
    data.volume = newVolume;  // State mutation by anyone
}

// TradeLimits.sol:69 — no modifier
function incrementOpenPositions(address trader) external {
    openPositionCount[trader]++;
}

// TradeLimits.sol:76 — no modifier
function decrementOpenPositions(address trader) external {
    if (openPositionCount[trader] > 0) {
        openPositionCount[trader]--;
    }
}
```

**Attack:**
1. Attacker calls `recordAndValidateVolume(victim, type(uint256).max)` → victim is permanently blocked from trading (volume always exceeds daily limit)
2. Attacker calls `incrementOpenPositions(victim)` repeatedly → victim hits `maxOpenPositions` and can't open new positions
3. Attacker calls `decrementOpenPositions(victim)` → reduces counter, potentially allowing victim to exceed actual position limit

**Impact:** Denial-of-service against any whitelisted trader. Can permanently prevent users from trading.

**Recommendation:** Add a `onlyContango` modifier or role check:
```solidity
modifier onlyContango() {
    require(msg.sender == contango, "Only Contango");
    _;
}
```

---

### C-02: PayableMulticall Enables Flash Loan Callback Hash Overwrites

**Severity:** CRITICAL
**Files:** `src/dependencies/PayableMulticall.sol:19-25` | `src/core/Contango.sol:63-64,481,486`

**Description:**

Contango inherits `PayableMulticall`, which allows batching multiple calls via `delegatecall`. The flash loan verification uses a single `callbackHash` state variable.

```solidity
// PayableMulticall.sol:22
results[i] = Address.functionDelegateCall(address(this), data[i]);

// Contango.sol:63-64
bytes32 private callbackHash;
bytes32 private tradeHash;
```

**Attack Scenario:**

A malicious actor constructs a `multicall` batch:
1. Call 1: Initiates `trade()` which sets `callbackHash = keccak256(legitimateData)` and starts flash loan
2. The flash loan provider calls back into Contango
3. Inside the callback, if the attacker can trigger another operation that overwrites `callbackHash`, the verification is broken

**Practical Exploitability:** The `multicall` itself runs sequentially (each delegatecall completes before the next), so the attack requires the flash loan callback to be triggered within a single delegatecall step. The real risk is:
- Flash loan provider calls `completeOpenFromFlashLoan()` during `_flash()` execution
- If the flash provider is compromised, it could call `multicall()` on Contango with data that overwrites `callbackHash` before returning

**Mitigating Factor:** The flash loan provider must be whitelisted via RouterGuard. However, this creates a **single point of failure** — if the flash provider is compromised or has an exploit, the callback hash mechanism can be bypassed.

**Recommendation:**
```solidity
// Use a reentrancy-style lock
bool private inFlash;

function _flash(...) private returns (bytes memory result) {
    require(!inFlash, "Flash in progress");
    inFlash = true;
    ...
    result = provider.flash(...);
    inFlash = false;
}
```

---

### C-03: completeOpenFromFlashLoan Has No Caller Validation

**Severity:** CRITICAL
**File:** `src/core/Contango.sol:216-225`

**Description:**

```solidity
function completeOpenFromFlashLoan(
    address, /* initiator */
    address repayTo,
    address asset,
    uint256 amount,
    uint256 fee,
    bytes calldata params
) external override returns (bytes memory result) {
    return encodeTradeAndHash(_completeOpen(IERC20(asset), amount + fee, _flashLoanCallback(params), repayTo));
}
```

This function is `external` with **no `msg.sender` validation**. Compare with `completeOpenFromFlashBorrow` (line 212) which validates `msg.sender == moneyMarket`.

The only protection is `_flashLoanCallback(params)` which checks `keccak256(params) == callbackHash`. But if an attacker:
1. Front-runs or observes the pending transaction
2. Knows the `params` data (which is the encoded FlashLoanCallback struct)
3. Calls `completeOpenFromFlashLoan()` before the legitimate flash provider does

Then the callback hash will match and the attacker's call will succeed, while the legitimate callback will fail (hash deleted).

**Mitigating Factor:** The attacker needs to know the exact `params` bytes, which include position ID, execution parameters, and instrument data. In practice, this data is constructed within the same transaction, making front-running difficult but not impossible on chains without private mempools.

**Additionally:** The `completeClose` callback (line 343) has the same pattern — no `msg.sender` validation, only hash check.

**Recommendation:**
```solidity
// Store expected callback sender
address private expectedCallbackSender;

function _flash(...) private {
    expectedCallbackSender = address(provider);
    callbackHash = keccak256(data);
    result = provider.flash(...);
    delete expectedCallbackSender;
}

function completeOpenFromFlashLoan(...) external {
    require(msg.sender == expectedCallbackSender, "Invalid callback sender");
    ...
}
```

---

## High Severity Findings

### H-01: Vault _deposit Underflow if Token Balance Drops Below Tracked Total

**Severity:** HIGH
**File:** `src/core/Vault.sol:61`

**Description:**

```solidity
uint256 available = token.balanceOf(address(this)) - tokenData.totalBalance;
```

If `token.balanceOf(address(this))` is ever less than `tokenData.totalBalance` (e.g., due to a fee-on-transfer token, rebasing token, or direct token rescue), this line **reverts with underflow** (Solidity 0.8+). This means:
- All deposits for that token permanently fail
- No recovery mechanism exists

**Attack:** Use a fee-on-transfer token. When Vault receives 100 tokens but only 98 arrive (2% fee), `totalBalance` is incremented by 100 but actual balance is 98. Next deposit: `98 - 100 = underflow → revert`.

**Mitigating Factor:** The Vault has a token whitelist (`setTokenSupport`), so the operator controls which tokens are enabled. However, some tokens can change fee behavior after deployment (e.g., USDT has a fee mechanism that's currently set to 0).

**Recommendation:** Use the actual received amount:
```solidity
uint256 balanceBefore = token.balanceOf(address(this));
token.transferOut(payer, address(this), amount);
uint256 received = token.balanceOf(address(this)) - balanceBefore;
tokenData.totalBalance += received;
```

---

### H-02: RouterGuard Owner is a Single EOA Without Timelock

**Severity:** HIGH
**File:** `src/security/RouterGuard.sol:20-22`

**Description:**

```solidity
constructor() Ownable() {
    _transferOwnership(msg.sender);
}
```

The RouterGuard owner (likely deployer EOA) can instantly:
- Whitelist a malicious router that drains all swap amounts
- Whitelist a malicious flash loan provider
- Remove legitimate routers mid-transaction

Unlike Contango (which uses `Timelock` for admin role), RouterGuard uses simple `Ownable`. Same issue applies to `AccessGate` and `TradeLimits`.

**Impact:** If the deployer key is compromised, attacker gains full control over:
1. Which DEX routers can execute swaps (can steal all swap funds)
2. Which flash loan providers can be used
3. Which wallets can trade (can lock everyone out)

**Recommendation:** Transfer ownership to a Timelock or multisig:
```solidity
routerGuard.transferOwnership(address(timelock));
accessGate.transferOwnership(address(timelock));
tradeLimits.transferOwnership(address(timelock));
```

---

### H-03: No Deadline Protection on Swap Execution

**Severity:** HIGH
**Files:** `src/utils/SpotExecutor.sol` | `src/core/Contango.sol:444-462`

**Description:**

The `ExecutionParams` struct does not include a deadline parameter. Swap execution relies entirely on the encoded `swapBytes` to contain a deadline, but:
1. There's no on-chain enforcement
2. If KyberSwap API returns swap data without a deadline, the order has no expiry
3. A validator/sequencer can hold the transaction and execute it when the price is unfavorable (MEV)

The `limitPrice` check (Contango.sol:457-461) provides slippage protection but not time-bound protection.

**Scenario:**
1. User submits trade at block N with limit price of 2000 USDC/ETH
2. Sequencer holds the transaction for 10 minutes
3. Price drops to 2001 USDC/ETH — still above limit
4. But user would have cancelled if they knew about the delay

**Recommendation:** Add deadline to `ExecutionParams`:
```solidity
struct ExecutionParams {
    address spender;
    address router;
    uint256 swapAmount;
    bytes swapBytes;
    IERC7399 flashLoanProvider;
    uint256 deadline;  // block.timestamp deadline
}
```

---

### H-04: Pausable Blocks Emergency Position Closures

**Severity:** HIGH
**File:** `src/core/Contango.sol:125`

**Description:**

```solidity
function tradeOnBehalfOf(...) public payable override returns (...) {
    _requireNotPaused();  // Blocks ALL operations
    ...
}
```

When paused (presumably during a security incident), users **cannot close or reduce their positions**. If the protocol is paused while a user's position approaches liquidation:
1. User cannot close their position via Contango
2. The underlying money market (Aave/Morpho) can still liquidate them
3. User loses funds that could have been salvaged

**Recommendation:** Allow closing (negative quantity) even when paused:
```solidity
function tradeOnBehalfOf(...) {
    if (tradeParams.quantity >= 0) _requireNotPaused();
    // Closures always allowed
    ...
}
```

---

## Medium Severity Findings

### M-01: Vault Withdrawal Follows Check-Effects-Interactions But Lacks Reentrancy Guard

**Severity:** MEDIUM
**File:** `src/core/Vault.sol:96-111`

**Description:**

The `_withdraw` function follows CEI pattern (balance reduced before transfer), and the contract inherits `ReentrancyGuard`. However, the `deposit`, `withdraw`, `depositNative`, and `withdrawNative` functions **do not use the `nonReentrant` modifier**. The `ReentrancyGuard` is inherited but **never applied**.

```solidity
contract Vault is IVault, ReentrancyGuard, AccessControl, Pausable {
    // ReentrancyGuard inherited but nonReentrant never used on any function
    function withdraw(...) public authorised(account) returns (uint256) {  // no nonReentrant
        return _withdraw(...);
    }
}
```

With a malicious ERC-777 token (or token with transfer hooks), an attacker could potentially re-enter during the transfer. The CEI pattern mitigates the classic reentrancy, but cross-function reentrancy (e.g., re-entering `deposit` during a `withdraw` transfer) could manipulate balances.

**Recommendation:** Add `nonReentrant` to all external state-changing functions, or remove `ReentrancyGuard` inheritance to avoid false security confidence.

---

### M-02: claimRewards Allows Permanent Claims After Position Closure

**Severity:** MEDIUM
**File:** `src/core/Contango.sol:676-685`

**Description:**

```solidity
function claimRewards(PositionId positionId, address to) external override {
    _requireNotPaused();
    if (positionNFT.exists(positionId)) positionNFT.validateModifyPositionPermissions(positionId);
    else if (lastOwner[positionId] != msg.sender) revert Unauthorised(msg.sender);
    _moneyMarket(positionId).claimRewards(positionId, _instrument.base, _instrument.quote, to);
}
```

After a position is fully closed:
- `lastOwner[positionId]` is set permanently
- The `lastOwner` can claim rewards indefinitely
- If the money market accumulates rewards after closure (unlikely but protocol-dependent), these can be claimed

**Impact:** Low financial impact in current design, but violates the principle that closed positions should have no residual authority.

---

### M-03: donatePosition Allows Unrestricted Transfer After Closure

**Severity:** MEDIUM
**File:** `src/core/Contango.sol:687-689`

**Description:**

```solidity
function donatePosition(PositionId positionId, address to) external override {
    _requireNotPaused();
    if (lastOwner[positionId] != msg.sender) revert Unauthorised(msg.sender);
```

The `donatePosition` function transfers `lastOwner` mapping to another address. This mapping was intended as a convenience for reward claiming, but it becomes a transferable claim on closed-position rewards without any of the NFT transfer protections (no approval check, no transfer event).

---

### M-04: Flash Loan Amount Not Validated Against Instrument Limits

**Severity:** MEDIUM
**File:** `src/core/Contango.sol:172-195`

**Description:**

The flash loan amount is computed from user-provided `execParams.swapAmount`:
```solidity
uint256 flashLoanAmount = tradeParams.cashflowCcy == Currency.Quote
    ? (execParams.swapAmount.toInt256() - tradeParams.cashflow).toUint256()
    : execParams.swapAmount;
```

There's no validation that `flashLoanAmount` is reasonable relative to the position size. An attacker could pass an extremely large `swapAmount` which:
1. Borrows excessive amounts via flash loan
2. The swap might partially fill or fail
3. Reverts due to slippage, but consumes gas and creates mempool noise

The `TradeLimits.validateTradeSize` checks `tradeParams.quantity`, not `execParams.swapAmount`.

---

### M-05: Infinite Token Approvals to Money Markets

**Severity:** MEDIUM
**File:** `src/core/Contango.sol:100-101`

**Description:**

```solidity
SafeERC20.forceApprove(instrument_.base, address(moneyMarket), type(uint256).max);
SafeERC20.forceApprove(instrument_.quote, address(moneyMarket), type(uint256).max);
```

Each position's money market proxy gets unlimited approval. If a money market implementation has a vulnerability, all tokens approved to it can be drained.

**Mitigating Factor:** Each position uses a separate clone (via `UnderlyingPositionFactory`), so compromise affects one position at a time. However, the approval is from Contango itself, which holds tokens during flash loan execution.

---

### M-06: Volume Tracking Uses execParams.swapAmount (User-Controlled)

**Severity:** MEDIUM
**File:** `src/core/Contango.sol:128`

**Description:**

```solidity
tradeLimits.recordAndValidateVolume(onBehalfOf, execParams.swapAmount);
```

`execParams.swapAmount` is entirely user-controlled. A user could:
1. Pass `swapAmount = 0` but use the `_bypassFlashLoanOnOpen` path (cashflow covers swap)
2. Execute trades without recording any volume
3. Bypass daily volume limits entirely

Conversely, passing an inflated `swapAmount` doesn't help the attacker (the swap would fail or return unfavorable rates).

---

### M-07: Spot Executor Retains Residual Token Approvals

**Severity:** MEDIUM
**File:** `src/utils/SpotExecutor.sol:35`

**Description:**

```solidity
SafeERC20.forceApprove(tokenToSell, execParams.spender, execParams.swapAmount);
```

After the swap, any unused approval remains. If the router only swaps part of the approved amount, the remaining approval persists. A compromised or upgraded router could later use this residual approval.

**Recommendation:** Reset approval after swap:
```solidity
Address.functionCall(execParams.router, execParams.swapBytes);
SafeERC20.forceApprove(tokenToSell, execParams.spender, 0);  // Clear residual
```

---

## Low Severity Findings

### L-01: AccessGate.whitelistedCount Can Underflow via Remove-Twice Pattern

**Severity:** LOW
**File:** `src/security/AccessGate.sol:31-37`

**Description:**

The `removeWallet` function properly checks `whitelistedWallets[wallet]` before decrementing, so this is actually safe. No vulnerability here — confirmed correct after manual review.

---

### L-02: No Event Emission for TradeLimits Configuration Changes

**Severity:** LOW
**File:** `src/security/TradeLimits.sol:30-40`

**Description:**

`setMaxTradeSize`, `setMaxDailyVolume`, and `setMaxOpenPositions` don't emit events. Off-chain monitoring can't detect when limits change.

---

### L-03: PayableMulticall Allows msg.value Reuse

**Severity:** LOW
**File:** `src/dependencies/PayableMulticall.sol:19`

**Description:**

```solidity
function multicall(bytes[] calldata data) external payable virtual returns (bytes[] memory results) {
```

In a multicall batch, `msg.value` is available to all delegatecalls. If multiple calls in the batch check `msg.value`, they all see the same value. This could lead to double-counting of ETH deposits in theory, though Vault's `depositNative` uses `msg.value` directly which would fail on the second call (insufficient ETH balance).

---

### L-04: Position ID Number Collision After Burn/Re-mint

**Severity:** LOW
**File:** `src/core/Contango.sol:91-108`

**Description:**

Position IDs include a sequential number. If a position is burned and a new one created with the same symbol/money market, the number increments. However, `lastOwner[oldPositionId]` retains the old owner, and `_moneyMarket(oldPositionId)` could still resolve to a valid (but empty) money market instance. The `claimRewards` path for burned positions could interact with stale state.

---

### L-05: validateTradeSize Uses abs() on User-Provided int256

**Severity:** LOW
**File:** `src/core/Contango.sol:127`

**Description:**

```solidity
tradeLimits.validateTradeSize(tradeParams.quantity > 0 ? uint256(tradeParams.quantity) : uint256(-tradeParams.quantity));
```

If `tradeParams.quantity == type(int256).min`, the negation `-(type(int256).min)` overflows. Solidity 0.8+ will revert, so this is a DoS vector for that specific value only. Extremely unlikely in practice.

---

## Informational / Design Notes

### I-01: Contango Inherits AccessControl But Doesn't Use DEFAULT_ADMIN_ROLE Guard on All Admin Functions

Admin functions use specific roles (OPERATOR_ROLE, EMERGENCY_BREAK_ROLE) which is correct. The `DEFAULT_ADMIN_ROLE` is only assigned to the Timelock and governs role grants. This is proper AccessControl usage.

### I-02: Position NFT isApprovedForAll Override

```solidity
function isApprovedForAll(address owner, address operator) public view override returns (bool) {
    return owner == operator || contangoContracts[operator] || super.isApprovedForAll(owner, operator);
}
```

This grants blanket approval to any address in `contangoContracts`. Adding a malicious contract to this mapping gives it full position control. The mapping is only modifiable by admin role, which requires Timelock. This is acceptable.

### I-03: Solidity Version and Compiler Settings

Using 0.8.27 with optimizer at 200 runs. `deny_warnings = true` ensures no silent issues. EVM target Cancun is appropriate for current deployments.

### I-04: Flash Loan Fee Handling

The protocol correctly passes flash loan fees to the borrower:
- Open: `amount + fee` is the total owed (line 224)
- Close: `amount + fee` is the total owed (line 348)

Fees are borrowed from the money market, increasing the position's debt. This is transparent and correct.

---

## Architecture Strengths

1. **Clone-per-position isolation:** Each position gets its own money market proxy via `UnderlyingPositionFactory.cloneDeterministic()`. A vulnerability in one position cannot drain another.

2. **Dual hash verification:** Both `callbackHash` (flash loan data integrity) and `tradeHash` (trade result integrity) are checked and cleared, preventing replay and tampering.

3. **Whitelisted wallet access:** `AccessGate` limits the protocol to known wallets with a hard cap (`maxWhitelistedWallets`), dramatically reducing attack surface.

4. **Router whitelist (RouterGuard):** Prevents arbitrary DEX router calls, which is the primary fund extraction vector in DeFi protocols.

5. **Trade limits (TradeLimits):** Rate limiting via daily volume, trade size, and position count adds defense-in-depth against fund drainage.

6. **Position permission model:** NFT-based ownership with proper ERC-721 approval checks prevents unauthorized position manipulation.

7. **Price-based slippage checks:** `limitPrice` validation in `_executeSwap` prevents unfavorable swap execution.

---

## Recommendations Summary

| ID | Severity | Finding | Fix |
|----|----------|---------|-----|
| C-01 | CRITICAL | TradeLimits/AccessGate no access control on state mutations | Add `onlyContango` modifier |
| C-02 | CRITICAL | PayableMulticall + callbackHash interaction | Add reentrancy lock to `_flash()` |
| C-03 | CRITICAL | completeOpenFromFlashLoan no msg.sender check | Store and validate expected callback sender |
| H-01 | HIGH | Vault deposit underflow with fee-on-transfer tokens | Use balance-before/after pattern |
| H-02 | HIGH | RouterGuard/AccessGate/TradeLimits owned by EOA | Transfer to Timelock or multisig |
| H-03 | HIGH | No deadline on swap execution | Add deadline field to ExecutionParams |
| H-04 | HIGH | Pause blocks emergency closures | Allow negative-quantity trades when paused |
| M-01 | MEDIUM | Vault inherits ReentrancyGuard but never uses it | Add `nonReentrant` to external functions |
| M-02 | MEDIUM | claimRewards permanent after closure | Add time-bound or one-time claim |
| M-03 | MEDIUM | donatePosition bypasses NFT transfer protections | Consider removing or adding event |
| M-04 | MEDIUM | Flash loan amount not bounded | Validate against position/instrument limits |
| M-05 | MEDIUM | Infinite approvals to money market proxies | Approve exact amounts per operation |
| M-06 | MEDIUM | Volume tracking uses user-controlled swapAmount | Derive volume from actual swap execution |
| M-07 | MEDIUM | Residual token approvals on SpotExecutor | Reset approval to 0 after swap |
| L-02 | LOW | No events on TradeLimits config changes | Add events |
| L-03 | LOW | msg.value reuse in multicall | Document risk, consider ETH tracking |

---

## Files Audited

| File | Lines | Findings |
|------|-------|----------|
| `src/core/Contango.sol` | 747 | C-02, C-03, H-04, M-02, M-03, M-04, M-05, M-06 |
| `src/core/Vault.sol` | 127 | H-01, M-01 |
| `src/core/Maestro.sol` | 81 | — |
| `src/core/PositionNFT.sol` | 63 | I-02 |
| `src/security/RouterGuard.sol` | 60 | H-02 |
| `src/security/AccessGate.sol` | 52 | C-01, H-02 |
| `src/security/TradeLimits.sol` | 90 | C-01, H-02, L-02 |
| `src/utils/SpotExecutor.sol` | 47 | H-03, M-07 |
| `src/utils/SimpleSpotExecutor.sol` | 50 | — |
| `src/dependencies/PayableMulticall.sol` | 28 | C-02, L-03 |
| `src/libraries/ERC20Lib.sol` | 109 | — |
| `src/libraries/MathLib.sol` | 17 | — |
| `src/libraries/DataTypes.sol` | 73 | — |
| `src/libraries/Roles.sol` | 12 | — |
| `src/moneymarkets/aave/AaveMoneyMarket.sol` | ~225 | — |
| `src/moneymarkets/morpho/MorphoBlueMoneyMarket.sol` | ~130 | — |
| `src/moneymarkets/ImmutableBeaconProxy.sol` | 20 | — |
| `src/moneymarkets/UnderlyingPositionFactory.sol` | 64 | — |

---

*This audit was performed through static analysis and manual code review. No tests were executed. Findings should be validated against the specific deployment configuration and on-chain state.*
