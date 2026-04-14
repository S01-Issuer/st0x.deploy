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
  diamond facet implementing `ICorporateActionsV1`. Schedules and applies
  corporate actions (stock splits today; further action types planned). Action
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
- `LibERC20Storage` — direct storage helpers used by the lazy-rebase migration
  to read/write OZ ERC20 balances without going through `_update`. **Tightly
  coupled to OZ v5 `ERC20Upgradeable` storage layout — see the SAFETY block in
  that file.**
- `LibRebase` — lazy rebase application: rewrites holder balances to the
  post-rebase basis on first touch, rather than applying a global multiplier.
  **Cursor advancement is load-bearing for fresh recipients — see audit history
  under `audit/2026-04-07-01/` for the inflation bug fix and the regression
  tests.**
- `LibTotalSupply` — rebase-aware `totalSupply` accounting that tracks
  per-cursor pots so the reported supply remains correct mid-migration.

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
