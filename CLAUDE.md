# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Overview

st0x.deploy is a Solidity project that extends
[rain.vats](https://github.com/rainlanguage/rain.vats) with domain-specific
deployment and vault contracts for the Stox protocol. It implements RWA
tokenization using receipt vaults wrapped in ERC4626-compatible vaults for DeFi
integration.

## Build & Test

Development environment is provided via Nix flake (pulls Foundry from `rainix`):

```shell
# Enter dev shell
nix develop

# Build
forge build

# Run all tests (unit + fork)
forge test

# Run a single test
forge test --match-test testStoxUnifiedDeployer

# Format (run before committing)
forge fmt

# CI commands (via rainix)
nix develop -c rainix-sol-test       # Full test suite
nix develop -c rainix-sol-static     # Static analysis (slither + forge fmt --check)
nix develop -c rainix-sol-legal      # REUSE license compliance
```

Fork tests require `RPC_URL_BASE_FORK` env var (set in `.env`). They validate
deployed contract codehashes against Base mainnet at a pinned block.

## Architecture

**Beacon Proxy + ERC4626 Vault Pattern:**

- `StoxReceiptVault` (extends rain.vats `OffchainAssetReceiptVault`) —
  receipt-based RWA vault with ERC1155 receipts
- `StoxWrappedTokenVault` (ERC4626 + ICloneableV2) — wraps the receipt vault,
  capturing rebases/dividends in price rather than supply
- `StoxWrappedTokenVaultBeacon` — `UpgradeableBeacon` with hardcoded
  implementation and owner from constants
- `StoxWrappedTokenVaultBeaconSetDeployer` — creates beacon proxy instances,
  references beacon by Zoltu address
- `StoxOffchainAssetReceiptVaultBeaconSetDeployer` — inherits upstream deployer
  with hardcoded config
- `StoxUnifiedDeployer` — atomically deploys a receipt vault + wrapped vault
  pair

**Diamond facet for corporate actions** (introduced by the corporate-actions PR
stack):

- `StoxCorporateActionsFacet` (`src/concrete/StoxCorporateActionsFacet.sol`) —
  diamond facet implementing `ICorporateActionsV1`. Will schedule and apply
  corporate actions (stock splits first; further action types planned). Action
  state is held in a doubly linked list of `CorporateActionNode`s ordered by
  `effectiveTime`, traversed in chronological order, with a bitmap tagging each
  node's action type. **The facet is delegatecalled by the vault — direct calls
  to the facet revert.**
- `ICorporateActionsV1` (`src/interface/ICorporateActionsV1.sol`) — external
  interface used by oracles and other onchain consumers.

**Corporate-action storage libraries** (`src/lib/`):

- `LibCorporateAction`, `LibCorporateActionNode` — linked list and lifecycle for
  scheduled actions. Storage lives at the ERC-7201 namespace
  `rain.storage.corporate-action.1`.
- `LibStockSplit` — stock split parameter validation and encode/decode.
- `LibRebaseMath` — shared `applyMultiplier(balance, Float)` primitive used by
  every rebase path (share side, totalSupply, receipt side). Single source of
  truth for the rasterize-one-multiplier-step operation.
- `LibERC20Storage` — direct storage helpers used by the lazy-rebase migration
  to read/write OZ ERC20 balances without going through `_update`. **Tightly
  coupled to OZ v5 `ERC20Upgradeable` storage layout — see the SAFETY block in
  that file and §Dependencies "Breaking dependency bumps".**
- `LibERC1155Storage` — direct storage helpers for OZ ERC-1155
  `_balances[id][account]`, used by receipt-side rebase migration. **Tightly
  coupled to OZ v5 `ERC1155Upgradeable` storage layout — same pin convention as
  `LibERC20Storage`.**
- `LibRebase` — lazy share-side rebase application: rewrites holder balances to
  the post-rebase basis on first touch, rather than applying a global
  multiplier. Cursor advancement runs even when `storedBalance == 0`; skipping
  it would let a subsequent write land at a stale cursor and re-apply every
  completed multiplier on the next `balanceOf` read, inflating the balance. The
  `testZeroBalanceAdvancesCursor*` tests in `LibRebase.t.sol` and the
  fresh-recipient tests in `StoxReceiptVault.t.sol` pin this.
- `LibReceiptRebase` — receipt-side analogue of `LibRebase`. Walks the vault's
  stock split list through cross-contract `ICorporateActionsV1` view calls and
  rewrites ERC-1155 `_balances` via `LibERC1155Storage`. Preserves the same
  zero-balance cursor advancement guard.
- `LibCorporateActionReceipt` — per-`(holder, id)` receipt-side cursor storage
  at the ERC-7201 namespace `rain.storage.corporate-action-receipt.1`. Lives on
  the receipt contract, not the vault.
- `LibTotalSupply` — rebase-aware `totalSupply` accounting that tracks
  per-cursor pots so the reported supply remains correct mid-migration.

**Receipt-side rebase coordination.** `StoxReceipt` overrides `_update` and
`balanceOf(account, id)` to rasterize receipt balances in lockstep with the
share-side rebase. Without this, a stock split on the share side would create an
arbitrage opportunity against the un-rebased receipts. The receipt reads stock
split multipliers from the vault via `ICorporateActionsV1.nextOfType` +
`getActionParameters`. Both sides use `LibRebaseMath.applyMultiplier` so
rasterization is bitwise-identical.

Storage isolation follows the diamond storage pattern: each library uses a fixed
namespaced storage slot. New state must live in a library storage struct, not on
the facet itself.

**ICloneableV2 pattern** (from rain.factory): contracts have dual `initialize`
overloads — `initialize(address)` always reverts (documents signature),
`initialize(bytes)` is the real initializer returning `ICLONEABLE_V2_SUCCESS`.

**Zoltu deterministic deployment**: All contracts have parameterless
constructors enabling deployment via the Zoltu factory for identical addresses
across all EVM networks. Pointer files in `src/generated/` contain deterministic
addresses and bytecodes.

**Production constants** are split by version — each version is fully
self-contained:

- `LibProdDeployV1` — V1 Base deployment addresses, codehashes, creation
  bytecodes
- `LibProdDeployV2` — V2 Zoltu addresses and codehashes from generated pointers

Address constants in `LibProdDeploy*` libraries serve as an audit trail of
deployed contracts — do not remove them even if they appear unreferenced in
source code.

Source contracts should reference addresses and codehashes through the versioned
`LibProdDeploy*` libraries, not import bare constants directly from
`src/generated/*.pointers.sol`. The pointer files are consumed only by the
deploy libraries.

## Dependencies

Git submodules managed via Foundry. Key remappings in `foundry.toml`:

- `rain.vats/` → receipt vault framework
- `rain.factory/` → clonable factory pattern (ICloneableV2)
- `rain.deploy/` → Zoltu deterministic deployment
- `rain.sol.codegen/` → pointer file generation
- `openzeppelin-contracts-upgradeable/` → ERC4626, ERC20, beacon proxies
- `rain.math.float/` → Rain Float decimal arithmetic (used by the
  corporate-actions rebase path for stock split multipliers)

### Breaking dependency bumps

Two submodule bumps are **breaking** for the corporate-actions stack and cannot
be treated as routine dependency updates.

**`openzeppelin-contracts-upgradeable` v5 (ERC20Upgradeable ERC-7201 layout).**
`src/lib/LibERC20Storage.sol` derives the ERC-7201 storage root in-source from
`keccak256("openzeppelin.storage.ERC20")` and reads offsets 0 / 2 within the
namespaced struct for `_balances` / `_totalSupply`. If OZ renames the namespace
string or reshuffles the struct layout — e.g. in a hypothetical v6 —
`underlyingBalance` / `setUnderlyingBalance` / `underlyingTotalSupply` silently
read and write the wrong slots. Symptoms would be catastrophic and invisible to
bytecode comparison. On bump:

1. Verify the namespace string in OZ still hashes to the same root (or update
   it); the constant derivation in `LibERC20Storage.sol` uses the formula
   directly, no separate pin is needed.
2. Re-run `LibERC20StorageTest` in full: `testGetBalanceMatchesOzBalanceOf`,
   `testSetBalanceVisibleToOzBalanceOf`, `testFuzzRoundTrip` drive an actual
   `ERC20Upgradeable` subclass and cross-check every library accessor against
   the OZ read path. Any layout drift fails here.
3. Verify the struct still has `_balances` at offset 0 and `_totalSupply` at
   offset 2. If either moved, the assembly reads in `LibERC20Storage` must be
   re-pinned.

**`openzeppelin-contracts-upgradeable` v5 — `ERC1155Upgradeable` ERC-7201
layout.** `src/lib/LibERC1155Storage.sol` (PR #7) hard-codes the ERC-7201
storage slot for OZ's ERC-1155 `_balances[id][account]` mapping at
`ERC1155_STORAGE_LOCATION = 0x88be…4500`. The nested-mapping slot derivation is
`keccak256(abi.encode(account, keccak256(abi.encode(id, ERC1155_STORAGE_LOCATION))))`
— two hashes, with `_balances` as the base at offset 0 of the namespaced struct.
Same failure mode as the ERC-20 pin: a layout reorder or namespace rename
silently remaps every receipt balance the rebase migration writes. On bump:

1. Re-derive `ERC1155_STORAGE_LOCATION` from the new namespace string and update
   the constant.
2. Re-run
   `test/src/lib/LibERC1155Storage.t.sol::testErc1155SlotConstantMatchesDerivation`
   — it pins the formula.
3. Re-run `LibERC1155StorageTest` in full: the runtime invariant tests
   (`testGetBalanceMatchesOzBalanceOf`, `testFuzzRoundTripSingleId`,
   `testPerIdAndPerAccountSlotIsolation`, etc.) drive an actual
   `ERC1155Upgradeable` subclass and cross-check every library accessor against
   the OZ read path.
4. Verify the struct still has `_balances` at offset 0. If it moved, the
   two-hash derivation in `LibERC1155Storage` must be re-pinned.

**`rain.math.float` (load-bearing: precision / rounding characteristics).**
`src/lib/LibStockSplit.sol` enforces multiplier bounds
(`trunc(1e18 * multiplier) ∈ [1, 1e36]`) against Rain Float's current precision
and rounding behaviour. `LibRebase.migratedBalance` and
`LibTotalSupply.effectiveTotalSupply` rely on Float's `toFixedDecimalLossy`
truncating toward zero with the exact precision characteristics that produce the
pinned regression outputs. If a bump changes rounding mode (e.g. half-even vs
truncate), precision of `div`, or representation of finite decimals, stored
stock split parameters that were valid at schedule time could produce different
rasterized balances on subsequent reads — a silent semantic change. On bump:

1. Re-review the bounds in `LibStockSplit.validateParameters` against the new
   precision characteristics; tighten or widen as appropriate.
2. Re-run `LibStockSplit.t.sol` in full (multiplier bounds).
3. Re-run `LibRebase.t.sol::testSequentialPrecision` — the pinned
   `1/3 × 3 × 1/3 × 3 → 96` regression is the canary for precision drift.
4. Re-run `LibTotalSupply.t.sol::testFuzzEffectiveTotalSupplyMatchesReference` —
   the reference-implementation fuzz will diverge if Rain Float's rounding path
   changes.

Both dependencies are submodules pinned at a specific commit SHA; a
`forge update` without the follow-up verification steps above is NOT safe on
this stack.

## Compiler Settings

- Solidity 0.8.25 (exact pin `=0.8.25` in contracts, `^0.8.25` in libraries)
- EVM target: Cancun
- Optimizer: 100,000 runs
- `bytecode_hash = "none"`, `cbor_metadata = false` — enables deterministic
  codehash comparison in fork tests

## Versioning

All source contracts in `src/` must consistently target the latest deployment
version. Do not reference older version constants (e.g., `LibProdDeployV1`) from
source contracts — older versions exist only as an audit trail and for fork
tests against prior deployments.

Production deployments are versioned (`LibProdDeployV1`, `LibProdDeployV2`,
etc.). Each version has its own constants file and may have a separate deploy
library. When making changes to contract source:

- Update `CHANGELOG.md` with the change under the current version heading
- Regenerate pointer files if creation bytecodes change
  (`forge script script/BuildPointers.sol`)
- Bump to a new version heading (`V3`, `V4`, ...) only when a deployed
  contract's address or codehash changes. Additive changes that produce no new
  contracts and do not alter any deployed bytecode should be appended under the
  existing version heading. New `LibProdDeploy*` libraries are introduced
  together with new version headings.

## Deployment

`script/Deploy.sol` dispatches based on `DEPLOYMENT_SUITE` env var. One contract
per suite to avoid Zoltu factory nonce issues:

- `stox-receipt` — deploys StoxReceipt
- `stox-receipt-vault` — deploys StoxReceiptVault
- `stox-wrapped-token-vault` — deploys StoxWrappedTokenVault
- `stox-wrapped-token-vault-beacon` — deploys StoxWrappedTokenVaultBeacon
  (depends on StoxWrappedTokenVault)
- `stox-wrapped-token-vault-beacon-set-deployer` — deploys
  StoxWrappedTokenVaultBeaconSetDeployer (depends on beacon)
- `stox-offchain-asset-receipt-vault-beacon-set-deployer` — deploys
  StoxOffchainAssetReceiptVaultBeaconSetDeployer (depends on StoxReceipt,
  StoxReceiptVault)
- `stox-unified-deployer` — deploys StoxUnifiedDeployer
- `stox-corporate-actions-facet` — deploys StoxCorporateActionsFacet

Manual deployment via GitHub Actions workflow (`manual-sol-artifacts.yaml`)
supports multiple networks.

## Naming Conventions

- **Test helpers must have descriptive names.** Do not use `_foo` / `_bar` /
  `_helper` as placeholder names for test helper functions — name them after
  what they do (`mintAndApprove`, `expectRevertOnZeroAddress`, etc.). This
  applies to test files only.
- **Production code may use the leading-underscore convention**
  (`_internalName`) to mark `internal` / `private` visibility, matching the
  Solidity / OpenZeppelin convention. Inherited overrides such as `_msgSender`,
  `_update`, `_beforeTokenTransfer` must keep their inherited names.

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant — run `rainix-sol-legal`
to validate.
