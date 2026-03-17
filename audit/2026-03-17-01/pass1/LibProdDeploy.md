# Pass 1: Security — A07: LibProdDeploy.sol

## Evidence of Thorough Reading

**File:** `src/lib/LibProdDeploy.sol` (24 lines)

**Library:** `LibProdDeploy` (line 5) — constants-only, no imports, no logic.

**Constants:**
| Constant | Line |
|---|---|
| `BEACON_INIITAL_OWNER` | 7 |
| `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 10-11 |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 14 |
| `STOX_WRAPPED_TOKEN_VAULT` | 17 |
| `STOX_UNIFIED_DEPLOYER` | 20 |
| `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` | 22-23 |

## Findings

### A07-1: Typo in constant name `BEACON_INIITAL_OWNER` [LOW]

Missing 'I' in "INITIAL" — should be `BEACON_INITIAL_OWNER`. Used consistently across the codebase so it compiles, but harms readability and searchability. This is a public API surface (other contracts reference it).

### A07-2: Pragma `^0.8.25` inconsistent with all other files using `=0.8.25` [LOW]

All other `.sol` files in `src/` and `script/` use `pragma solidity =0.8.25` (exact pin). This file uses `^0.8.25` (range). While benign in practice (the compiler version is controlled by `foundry.toml`), it's an inconsistency that could cause confusion.

### A07-3: ENS comment for BEACON_INIITAL_OWNER is unverifiable [INFO]

The comment `/// rainlang.eth` for `BEACON_INIITAL_OWNER` provides no Basescan link unlike other constants. ENS resolution cannot be verified statically.

### A07-4: `STOX_WRAPPED_TOKEN_VAULT` constant is defined but never referenced [INFO]

The constant at line 17 is not used by any contract in `src/` or `script/`. May be dead code or reserved for future use.

### A07-5: Codehash validity depends on fork tests [INFO]

`PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` is verified by the prod fork test. Sound approach — confirm CI runs fork tests.

### A07-6: Basescan link format inconsistency [INFO]

One link includes `#code` suffix while others don't. Minor formatting inconsistency.

### A07-7: Basescan links could not be independently verified [INFO]

Unable to verify that the Basescan URLs match the hardcoded addresses without web access.
