# Pass 1: Security — StoxUnifiedDeployer.sol

## Evidence of Thorough Reading

**File:** `src/concrete/deploy/StoxUnifiedDeployer.sol` (45 lines)

**Contract:** `StoxUnifiedDeployer` (line 19) — no constructor, no state variables, no inheritance.

**Functions:**

| Function | Line | Visibility | Mutability |
|---|---|---|---|
| `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config)` | 35 | external | state-changing |

**Events:** `Deployment(address sender, address asset, address wrapper)` at line 25 (none indexed).

**Types/Errors/Constants:** None defined in this file. All types and constants are imported.

**Imported constants used (from `src/lib/LibProdDeployV1.sol`):**
- `LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER`: `0x2191981Ca2477B745870cC307cbEB4cB2967ACe3`
- `LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER`: `0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB`

**Imported types used:**
- `OffchainAssetReceiptVaultBeaconSetDeployer` — external call target for receipt vault creation
- `OffchainAssetReceiptVaultConfigV2` — calldata struct passed through to the upstream deployer
- `OffchainAssetReceiptVault` — return type of receipt vault creation
- `StoxWrappedTokenVaultBeaconSetDeployer` — external call target for wrapped vault creation
- `StoxWrappedTokenVault` — return type of wrapped vault creation

**Slither annotations:** `slither-disable-next-line reentrancy-events` at line 34, with an inline comment explaining the rationale.

## Security Checklist

- **Input validation:** `config` is forwarded directly to `OffchainAssetReceiptVaultBeaconSetDeployer.newOffchainAssetReceiptVault`, which performs its own validation. `StoxWrappedTokenVaultBeaconSetDeployer.newStoxWrappedTokenVault` validates `asset != address(0)`, which is satisfied since the upstream deployer returns a fresh contract address. No additional validation needed here.
- **Access controls:** Callable by anyone (permissionless factory). Intentional — vault ownership is determined by `config.vaultConfig.receiptVaultConfig.receiptVaultConfig.admin` (set deep inside `config`), not by the caller.
- **Reentrancy:** Two sequential external calls to hardcoded trusted deployer addresses. This contract has zero storage and holds no balances. A reentrant call would only deploy another independent vault pair. The slither suppression annotation is justified and documented.
- **Atomicity:** Both external calls occur in the same transaction with no `try/catch`. If the second call reverts, the entire transaction reverts and no partial state is left. The `asset` address returned by the first call is passed directly to the second — no opportunity for substitution.
- **Arithmetic safety:** No arithmetic in this contract.
- **Assembly:** No inline assembly.
- **Custom errors:** No `revert` statements in this contract. Downstream deployers use custom errors exclusively.
- **Return value verification:** The return value of `newStoxWrappedTokenVault` is captured and used in the event. The return value of `newOffchainAssetReceiptVault` is captured and used as the asset argument to the second call. Neither return value is silently discarded.
- **Address hardcoding:** Deployer addresses are compile-time constants from `LibProdDeployV1`, providing a git-auditable trail. No runtime address manipulation is possible.
- **Prior audit A05-3 (typo BEACON_INIITAL_OWNER):** Fixed in `LibProdDeployV1.sol` — constant is now `BEACON_INITIAL_OWNER`.
- **Prior audit A05-4 (inconsistent pragma):** The library pragma convention (`^`) vs concrete pragma (`=`) is documented as intentional in `CLAUDE.md` and the process audit. Not a defect.

## Findings

No findings.
