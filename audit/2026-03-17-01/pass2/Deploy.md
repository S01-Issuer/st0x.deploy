# Pass 2: Test Coverage — A01: Deploy.sol

## Evidence of Thorough Reading

**File:** `script/Deploy.sol` (94 lines)

**Contract:** `Deploy` (line 32) — inherits `Script` from forge-std

**File-level Constants:**
| Constant | Line(s) |
|---|---|
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | 23-24 |
| `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` | 27 |
| `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` | 30 |

**Functions:**
| Function | Line | Visibility |
|---|---|---|
| `deployOffchainAssetReceiptVaultBeaconSet(uint256)` | 37 | `internal` |
| `deployWrappedTokenVaultBeaconSet(uint256)` | 55 | `internal` |
| `deployUnifiedDeployer(uint256)` | 69 | `internal` |
| `run()` | 80 | `public` |

## Test Search

Grepped `test/` for `Deploy`, `deployOffchainAssetReceiptVaultBeaconSet`, `deployWrappedTokenVaultBeaconSet`, `deployUnifiedDeployer`, `DEPLOYMENT_SUITE`. No test file imports, instantiates, or exercises the `Deploy` script contract or any of its functions.

## Findings

### P2-DEPLOY-1: Zero test coverage for the Deploy script [LOW]

The `Deploy` contract has no test coverage. None of its four functions are exercised by any test. The dispatch logic in `run()` (lines 80-93) is particularly important to test because:
- A typo in `DEPLOYMENT_SUITE` string literals or comparisons would silently cause the wrong deploy path or always revert
- The correct `initialOwner` (`BEACON_INIITAL_OWNER`) must be passed to both beacon set deployers
- The script is the production entry point for all deployments

While Forge deploy scripts are commonly untested (they run in a special `vm.broadcast` context), the dispatch logic and config wiring are testable and carry meaningful risk if wrong.
