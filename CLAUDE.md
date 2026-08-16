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
across all EVM networks. `script/BuildPointers.sol` regenerates the top-level
`src/generated/*.pointers.sol` (deterministic address + creation/runtime
bytecode). Each release also FREEZES its exact bytecode in a per-tag snapshot
under `src/generated/<tag>/*.pointers.sol` (`0_1_1/`, `0_1_2/`, `0_1_3/`, …);
`LibProdDeployV4` imports and aliases those frozen constants rather than
inlining bytecode. BuildPointers rewrites ONLY the top-level pointers, so a
frozen historical snapshot must never be regenerated or mutated — that keeps a
past release reproducible and verifiable after the current build diverges.

**Production constants** are split by version — each version is fully
self-contained:

- `LibProdDeployV1` — V1 Base deployment addresses, codehashes, creation
  bytecodes
- `LibProdDeployV2` — V2 Zoltu addresses and codehashes from generated pointers
- `LibProdDeployV4` — the current production set. Within V4, each release is
  suffixed by st0x's own release tag (`_0_1_1`, `_0_1_2`, `_0_1_3`, …), and
  `DEPLOY_TAG` names the tag the current source compiles and deploys against.
  (There is no V3 — the never-deployed phantom lib was removed.)

Address constants in `LibProdDeploy*` libraries serve as an audit trail of
deployed contracts — do not remove them even if they appear unreferenced in
source code.

Source contracts should reference addresses and codehashes through the versioned
`LibProdDeploy*` libraries, not import bare constants directly from
`src/generated/*.pointers.sol`. The pointer files are consumed only by the
deploy libraries.

## Governance

Admin power over the production deployment is (post-migration) held by a
per-chain **governance timelock** — an unmodified OZ `TimelockController` that
owns every production receipt vault and holds the authoriser's seven `_ADMIN`
roles, with the token-owner Safe as sole proposer/canceller/ executor and a 48h
min delay. The Safe keeps the direct action roles
(`DEPOSIT`/`WITHDRAW`/`CERTIFY`); only admin surfaces are delay-gated.
Constants + invariants live in `src/lib/LibTimelockInvariants.sol`;
`timelockForChainId(block.chainid)` is the only sanctioned way for a script to
resolve the chain's timelock. Scripts authoring Safe bundles that touch
`onlyOwner`/`_ADMIN` surfaces must route them through `timelock.schedule(...)` →
(≥48h) → `timelock.execute(...)`. Full role model, rollout state, and runbook:
`docs/TIMELOCK.md`.

## Dependencies

Soldeer packages, not git submodules. They are declared as exact semver pins in
`foundry.toml`'s `[dependencies]`, locked in `soldeer.lock`, and installed by
`forge soldeer install` into `dependencies/` (`libs = ['dependencies']`, so
there is no `lib/`). Nothing here is a gitlink and there is no `.gitmodules` —
rainix CI enforces that with its `no-submodules` check.

Every import prefix carries the pinned version: `<package>-<version>/`. Soldeer
generates them into `remappings.txt`, which is the live list. Key packages:

- `rain-vats-0.1.6/` → receipt vault framework
- `rain-factory-0.1.1/` → clonable factory pattern (ICloneableV2)
- `rain-deploy-0.1.4/` → Zoltu deterministic deployment
- `rain-sol-codegen-0.1.0/` → pointer file generation
- `@openzeppelin-contracts-upgradeable-5.7.0/` → ERC4626, ERC20, beacon proxies
- `rain-math-float-0.1.1/` → Rain Float decimal arithmetic (used by the
  corporate-actions rebase path for stock split multipliers)

The one `remappings` entry in `foundry.toml` is unrelated to the above: it
bridges the unversioned `@openzeppelin/contracts/` prefix that a third-party
dependency's own source hard-codes.

`remappings.txt` additionally carries two **version-bridge** lines pointing the
old `@openzeppelin-contracts-5.6.1/` and
`@openzeppelin-contracts-upgradeable-5.6.1/` prefixes at the 5.7.0 install.
These exist because `rain-vats-0.1.6` still imports the 5.6.1 prefixes in its
own source; they can be dropped once rain-vats republishes against 5.7.0. Note
`forge soldeer install` REGENERATES `remappings.txt` from `[dependencies]` and
will delete them — re-apply after any soldeer run, or the build breaks on
rain-vats' transitive imports.

### Breaking dependency bumps

Two dependency bumps are **breaking** for the corporate-actions stack and cannot
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

Both are Soldeer packages pinned at an exact semver version in `foundry.toml`'s
`[dependencies]`, so `forge update` — the git-submodule command — does nothing
here. `forge soldeer update` is what moves them, and because the version is part
of the import prefix, a bump also changes every
`@openzeppelin-contracts-upgradeable-5.7.0/` and `rain-math-float-0.1.1/` import
across `src/`, `test/` and `script/`. Soldeer regenerates `remappings.txt`; it
does not rewrite those imports, so they are updated by hand in the same commit.
Bumping without the follow-up verification steps above is NOT safe on this
stack.

## Compiler Settings

- Solidity 0.8.25 (exact pin `=0.8.25` in contracts, `^0.8.25` in libraries)
- EVM target: Cancun
- Optimizer: 5000 runs — `StoxReceiptVault` is the contract that binds against
  EIP-170 (24,576-byte runtime limit), and 5000 keeps it under the limit while
  the rest of the suite stays well clear. The setting is a runtime-gas vs
  deploy-bytecode tradeoff (high values inline aggressively for fast runtime at
  the cost of deployed bytecode size). The margin is thin and sensitive to vault
  source changes and dependency-tree bytecode shifts — re-check
  `StoxReceiptVault`'s `forge build --sizes` runtime margin on any such change.
  The corresponding `foundry.toml` comment block flags this; both must stay in
  sync.
- `via_ir` is OFF. IR was tried (#144) and made the vault larger for our
  inheritance shape, opposite of the goal. Don't enable without a measurement
  showing it now helps.
- `bytecode_hash = "none"`, `cbor_metadata = false` — enables deterministic
  codehash comparison in fork tests
- All settings live in `[profile.default]`. Do NOT split deploy and test
  profiles: tests pin `addr.codehash` against constants in `LibProdDeploy*`
  files that are derived from the _deployed_ bytecode. If tests compile with
  different optimizer settings than the deploy, every codehash assertion fails.
  Single-profile is the codehash-pinning convention.

## Versioning

All source contracts in `src/` must consistently target the latest deployment
version. Do not reference older version constants (e.g., `LibProdDeployV1`) from
source contracts — older versions exist only as an audit trail and for fork
tests against prior deployments.

Production deployments are versioned (`LibProdDeployV1`, `LibProdDeployV2`,
etc.). Each version has its own constants file and may have a separate deploy
library. When making changes to contract source:

- Update `CHANGELOG.md` with the change under the current version heading
- Regenerate the top-level pointer files if creation bytecodes change
  (`forge script script/BuildPointers.sol`), and freeze a new
  `src/generated/<tag>/` snapshot for the new release tag — never regenerate a
  historical tag's snapshot.
- Within a `LibProdDeploy*` library, a release that moves any deployed
  contract's address or codehash adds a new release-tag suffix (`_0_1_N`) plus
  its frozen snapshot, keeping prior tags as historicals. Additive changes that
  produce no new contracts and alter no deployed bytecode append under the
  existing tag. A new `LibProdDeploy*` library (a new V-generation) is a rarer,
  larger change for a wholesale deployment regeneration.

## Deployment

Production deploys run the audited, version-specific script
`script/DeployProdV4_0_1_1.sol` — never the current source. It ships the stored
audited-0.1.1 creation bytecode (`LibProdDeployV4.*_CREATION_CODE_0_1_1`, the
exact bytes the 0.1.1 audit covers) and asserts each contract against its
`_0_1_1` address/codehash pin, so the on-chain result is the audited deployment
regardless of what the current source compiles to. Each dispatch deploys one
contract suite (`DEPLOYMENT_SUITE`, one contract per suite to avoid Zoltu
factory nonce issues) to a single bootstrap network (`DEPLOYMENT_NETWORK` —
Ethereum or HyperEVM), via the `manual-sol-artifacts-0-1-1.yaml` GitHub Actions
workflow; the Zoltu deploy is idempotent per network. Suites are deployed in the
workflow's listed order — later suites reference earlier ones via dependency
pointers, so an out-of-order run trips the dep-codehash check. The orchestrator
(introduced at 0.1.2) is not part of the audited 0.1.1 set.

The rolling `candidate` snapshot (`src/generated/candidate/`) is NEVER a deploy
target — it exists only so tests exercise the current source and
`testCandidateSelfConsistent` pins source↔snapshot integrity. When a later
version is audited it gets its own frozen numbered snapshot (cut from
`candidate` by a `sol-vX.Y.Z` release tag; see `script/cut-release.sh`) and its
own `script/DeployProdV4_0_1_N.sol`. The frozen V1/V2 deployments in
`LibProdDeployV1` / `LibProdDeployV2` are an audit trail and are not
redeployable from the current source.

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
