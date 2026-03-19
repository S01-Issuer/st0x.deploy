# Pass 1: Security -- StoxUnifiedDeployer.sol

## Evidence of Thorough Reading

**File:** `src/concrete/deploy/StoxUnifiedDeployer.sol` (45 lines)

**Contract:** `StoxUnifiedDeployer` (line 19) -- no constructor, no state variables, no inheritance.

**Functions:**

| Function | Line | Visibility | Mutability |
|---|---|---|---|
| `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config)` | 35 | external | state-changing |

**Events:** `Deployment(address sender, address asset, address wrapper)` at line 25 (no indexed parameters).

**Types/Errors/Constants:** None defined in this file. All types and constants are imported.

**Imports (lines 4-12):**
- `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultConfigV2`, `OffchainAssetReceiptVault` from ethgild
- `StoxWrappedTokenVaultBeaconSetDeployer` from `./StoxWrappedTokenVaultBeaconSetDeployer.sol`
- `LibProdDeployV2` from `../../lib/LibProdDeployV2.sol`
- `StoxWrappedTokenVault` from `../StoxWrappedTokenVault.sol`

**Imported constants used (from `src/lib/LibProdDeployV2.sol`):**
- `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` -- Zoltu deterministic address
- `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` -- Zoltu deterministic address

**Slither annotations:** `slither-disable-next-line reentrancy-events` at line 34, with `@dev` comment (lines 29-31) explaining the contract is stateless so reentrancy only creates independent vault pairs.

## Security Checklist

- **Input validation:** `config` is forwarded directly to `OffchainAssetReceiptVaultBeaconSetDeployer.newOffchainAssetReceiptVault`, which validates `config.receiptVaultConfig.receipt == address(0)` and `config.initialAdmin != address(0)`. The returned `asset` address (always nonzero from a fresh deployment) is passed to `newStoxWrappedTokenVault`, which validates `asset != address(0)`. No additional validation needed here.
- **Access controls:** Callable by anyone (permissionless factory). Intentional -- vault admin/ownership is determined by fields inside `config`, not by the caller.
- **Reentrancy:** Two sequential external calls to hardcoded trusted deployer addresses. This contract has zero storage and holds no balances. The slither suppression annotation is justified and documented.
- **Atomicity:** Both external calls occur in the same transaction with no `try/catch`. If the second call reverts, the entire transaction reverts and no partial state is left. The `asset` address returned by the first call is passed directly to the second -- no opportunity for substitution.
- **Arithmetic safety:** No arithmetic in this contract.
- **Assembly:** No inline assembly.
- **Custom errors:** No `revert` statements in this contract. Downstream deployers use custom errors exclusively.
- **Return value handling:** Return values of both external calls are captured and used -- `asset` as input to the second call, `wrappedTokenVault` in the event emission. Neither is silently discarded.
- **Address hardcoding:** Deployer addresses are compile-time constants from `LibProdDeployV2` (Zoltu deterministic addresses), providing a git-auditable trail. No runtime address manipulation is possible.

## Findings

No findings. The contract is a minimal stateless deployer with correct delegation of validation to downstream contracts, proper return value handling, justified reentrancy annotation, and atomic execution guarantees.
