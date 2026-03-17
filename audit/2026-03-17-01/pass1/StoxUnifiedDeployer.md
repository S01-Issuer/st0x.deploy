# Pass 1: Security — A05: StoxUnifiedDeployer.sol

## Evidence of Thorough Reading

**File:** `src/concrete/deploy/StoxUnifiedDeployer.sol` (41 lines)

**Contract:** `StoxUnifiedDeployer` (line 19) — no constructor, no state variables, no inheritance.

**Functions:**
| Function | Line | Visibility | Mutability |
|---|---|---|---|
| `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config)` | 31 | external | state-changing |

**Events:** `Deployment(address sender, address asset, address wrapper)` at line 25 (none indexed).

**Types/Errors/Constants:** None defined in this file. All types imported.

**Hardcoded Addresses (from `src/lib/LibProdDeploy.sol`):**
- `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER`: `0x2191981Ca2477B745870cC307cbEB4cB2967ACe3`
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER`: `0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB`

## Security Checklist Results

- **Input validation:** `config` forwarded directly to downstream deployer which performs its own validation. No issue.
- **Access controls:** Callable by anyone (permissionless factory). Intentional — vault ownership determined by `config.initialAdmin`, not caller.
- **Reentrancy:** Two sequential external calls to hardcoded trusted deployer addresses. Zero state in this contract — nothing to exploit via reentrancy.
- **Atomicity:** Both calls in same transaction, no try/catch. If second reverts, entire tx reverts. No partial state.
- **Custom errors only:** No `revert` statements in this contract. Downstream deployers use custom errors exclusively.

## Findings

### A05-1: No codehash verification for beacon set deployer addresses [INFO]

The prod test verifies the unified deployer's codehash but not the codehashes of the two beacon set deployer addresses it depends on.

### A05-2: Event parameters not indexed [INFO]

The `Deployment` event leaves all parameters non-indexed. Matches the pattern in companion deployers — a deliberate codebase-wide choice.

### A05-3: Typo in BEACON_INIITAL_OWNER constant name [INFO]

`LibProdDeploy.BEACON_INIITAL_OWNER` — "INIITAL" should be "INITIAL". Used consistently so it compiles, but harms readability.

### A05-4: Inconsistent pragma style [INFO]

`StoxUnifiedDeployer.sol` uses `=0.8.25` (exact pin) while `LibProdDeploy.sol` uses `^0.8.25` (range). Benign but inconsistent.
