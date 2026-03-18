# Pass 3 — Documentation: StoxUnifiedDeployer.sol

**Agent:** A06
**File:** `src/concrete/deploy/StoxUnifiedDeployer.sol`
**Date:** 2026-03-18

---

## Evidence of Thorough Reading

**Contract:** `StoxUnifiedDeployer`

**Functions:**
| Name | Line |
|---|---|
| `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config)` | 35 |

**Events:**
| Name | Line |
|---|---|
| `Deployment(address sender, address asset, address wrapper)` | 25 |

**Types, errors, constants:** None defined in this file.

---

## NatSpec Inventory

### Contract-level (lines 14–18)

- `@title StoxUnifiedDeployer` — present
- `@notice` — present, describes atomic deployment of a vault pair with hardcoded beacon sets
- `@dev` — absent (not required, but see finding below)

### Event `Deployment` (lines 20–25)

- Bare `///` description (acts as `@notice`) — present: "Emitted when a new OffchainAssetReceiptVault and StoxWrappedTokenVault are deployed."
- `@param sender` — present
- `@param asset` — present
- `@param wrapper` — present

All three event parameters are documented. No return value. No indexed parameters.

### Function `newTokenAndWrapperVault` (lines 27–44)

- `@notice` — present
- `@param config` — present, describes the `OffchainAssetReceiptVaultConfigV2` argument and notes its asset address is forwarded to the wrapper deployer
- `@return` — not applicable (function has no return value)
- `@dev` — absent (see finding below)

---

## Documentation Accuracy Review

### `@param config` accuracy

The `@param` states: "The configuration for the OffchainAssetReceiptVault. The resulting asset address is used to deploy the StoxWrappedTokenVault." This accurately describes the function body (lines 36–41): `config` is passed to `newOffchainAssetReceiptVault`, and the returned `asset` address is then forwarded to `newStoxWrappedTokenVault`.

### Event `@param asset` accuracy

Documented as "The address of the deployed OffchainAssetReceiptVault." The emitted value is `address(asset)` on line 43 where `asset` is the `OffchainAssetReceiptVault` returned by the beacon set deployer. Accurate.

### Event `@param wrapper` accuracy

Documented as "The address of the deployed StoxWrappedTokenVault." The emitted value is `address(wrappedTokenVault)` on line 43. Accurate.

### Event `@param sender` accuracy

Documented as "The address that initiated the deployment." The emitted value is `msg.sender` on line 43. Accurate.

### Reentrancy note placement

Lines 31–33 contain a reentrancy safety justification written as a regular `//` comment rather than a `///` NatSpec `@dev` comment. This note documents a security decision (why no `nonReentrant` guard is needed) but will not appear in any generated documentation or ABI tooling. Developers relying on generated docs will not see the rationale.

---

## Findings

### A06-P3-1 — LOW: Reentrancy justification is outside NatSpec

**Severity:** LOW

**Location:** `src/concrete/deploy/StoxUnifiedDeployer.sol`, lines 31–33

**Description:**

The reentrancy safety rationale at lines 31–33 is written as plain `//` comments, not as `///` NatSpec `@dev` documentation. Solidity's NatSpec processor does not include `//` comments in generated documentation, so this rationale is invisible to any consumer reading the ABI documentation, IDE tooltips, or `forge doc` output.

The contract deliberately omits a `nonReentrant` guard; the reason (statelessness — no storage, no balances) is a security-relevant design decision. It belongs in `@dev` so it is retained in generated artifacts and communicated to integrators.

**Evidence:**

```solidity
// Reentrancy is not exploitable here because this contract is entirely
// stateless — no storage, no balances. A reentrant call would just create
// another independent vault pair.
// slither-disable-next-line reentrancy-events
function newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external {
```

**Proposed fix:** See `.fixes/A06-P3-1.md`.

---

*No other LOW+ findings. All NatSpec tags are accurate against the implementation. All public/external functions have `@notice` and `@param` where applicable. The `Deployment` event is fully documented.*
