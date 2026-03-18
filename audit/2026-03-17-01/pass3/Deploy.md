# Pass 3: Documentation — A01: Deploy.sol

## Evidence of Thorough Reading

**File:** `script/Deploy.sol` (94 lines)

**Contract:** `Deploy` (line 32) — inherits `Script`

**Functions:**
| Function | Line | Visibility |
|---|---|---|
| `deployOffchainAssetReceiptVaultBeaconSet(uint256)` | 37 | `internal` |
| `deployWrappedTokenVaultBeaconSet(uint256)` | 55 | `internal` |
| `deployUnifiedDeployer(uint256)` | 69 | `internal` |
| `run()` | 80 | `public` |

**Constants:**
| Constant | Line(s) |
|---|---|
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | 23-24 |
| `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` | 27 |
| `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` | 30 |

## Documentation Review

| Element | NatSpec? | Accurate? |
|---|---|---|
| Constants `@dev` | Yes (lines 21, 26, 29) | Yes |
| `deployOffchainAssetReceiptVaultBeaconSet` `@notice` | Yes (lines 33-36) | See A01-P3-1 |
| `deployWrappedTokenVaultBeaconSet` `@notice` | Yes (lines 51-54) | See A01-P3-1 |
| `deployUnifiedDeployer` `@notice` | Yes (line 68) | Yes |
| `run()` `@notice` | Yes (lines 77-79) | Yes |
| `@param deploymentKey` | Missing on all internal functions | See A01-P3-2 |

## Findings

### A01-P3-1: NatSpec propagates `BEACON_INIITAL_OWNER` typo [LOW]

Lines 35 and 53 reference `BEACON_INIITAL_OWNER` in NatSpec comments, propagating the typo from `LibProdDeploy`. When the constant is renamed (per A07-1), these comments must be updated too.

### A01-P3-2: Internal deploy functions missing `@param` for `deploymentKey` [LOW]

All three internal deploy functions (`deployOffchainAssetReceiptVaultBeaconSet`, `deployWrappedTokenVaultBeaconSet`, `deployUnifiedDeployer`) take a `uint256 deploymentKey` parameter but have no `@param` tag documenting it.

### A01-P3-3: Constants lack semantic NatSpec [INFO]

The three `DEPLOYMENT_SUITE_*` constants have `@dev` comments saying they are "deployment suite names" but don't explain what a deployment suite is or how the constants are used in the dispatch logic.
