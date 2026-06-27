# st0x.deploy

Deployment and extension contracts for
[rain.vats](https://github.com/rainlanguage/rain.vats) that are domain-specific
for st0x. Implements RWA tokenization with receipt vaults wrapped in
ERC4626-compatible vaults for DeFi integration.

## Prerequisites

- [Nix](https://nixos.org/) (provides Foundry and all dependencies)

## Getting Started

```shell
nix develop
forge build
forge test
```

Fork tests require `RPC_URL_BASE_FORK` in `.env`.

## Architecture

```
                      ┌──────────────────────────────────────┐
                      │         StoxUnifiedDeployer          │
                      │  (atomically deploys vault + wrap)   │
                      └─────────────┬────────────────────────┘
                                    │ deploys pair
                ┌───────────────────┴───────────────────┐
                ▼                                       ▼
┌──────────────────────────┐          ┌──────────────────────────────┐
│    StoxReceiptVault      │          │   StoxWrappedTokenVault      │
│ (OffchainAssetReceipt    │◄─────────│   (ERC4626 wrapper)          │
│  Vault + rebase)         │ wraps    │   captures rebases in price  │
└──────────┬───────────────┘          └──────────────────────────────┘
           │ issues                           ▲
           ▼                                  │ beacon proxy
┌──────────────────────────┐   ┌──────────────────────────────┐
│      StoxReceipt         │   │ StoxWrappedTokenVaultBeacon   │
│  (ERC1155 + rebase)      │   │ (UpgradeableBeacon)           │
└──────────────────────────┘   └──────────────────────────────┘
           │
           │ delegatecall
           ▼
┌──────────────────────────┐
│ StoxCorporateActionsFacet│
│ (diamond facet)          │
│ ICorporateActionsV1      │
└──────────────────────────┘
           │ (facet + concrete contracts use)
┌──────────┴─────────────────────────────────────────────┐
│                    src/lib/                             │
│  Corporate-actions core                                 │
│    LibCorporateAction     — linked list + storage       │
│    LibCorporateActionNode — traversal with filters      │
│    LibStockSplit          — validation + decode         │
│                                                         │
│  Rebase math / migration                                │
│    LibRebase              — share-side lazy migration   │
│    LibReceiptRebase       — receipt-side lazy migration │
│    LibRebaseMath          — shared multiplier primitive │
│    LibTotalSupply         — per-cursor pot accounting   │
│                                                         │
│  Namespaced storage access                              │
│    LibERC20Storage        — OZ ERC20 slot access        │
│    LibERC1155Storage      — OZ ERC1155 slot access      │
│    LibCorporateActionReceipt — receipt cursor storage   │
│                                                         │
│  Production deploy constants                            │
│    LibProdDeployV1 / V2 / V2BaseOverrides / V3          │
│    LibProdTokensBase                                    │
└────────────────────────────────────────────────────────┘
```

### Token Topology (per deposit)

| Contract                | Standard | Purpose                                  |
| ----------------------- | -------- | ---------------------------------------- |
| `StoxReceipt`           | ERC-1155 | Proof of deposit, receipt-id granularity |
| `StoxReceiptVault`      | ERC-20   | Fungible vault shares, rebase-aware      |
| `StoxWrappedTokenVault` | ERC-4626 | Wraps shares, captures rebases in price  |

### Corporate Actions

The corporate actions system adds stock split support via a diamond facet that
is delegatecalled by the vault. Key design choices:

- **No stored status** — an action is complete when
  `effectiveTime <= block.timestamp`
- **Lazy migration** — balances rasterize on first interaction after a split
- **Sequential precision** — each multiplier truncates independently (no
  cumulative product)
- **Per-cursor pots** — `totalSupply` improves precision as accounts migrate

See `ICorporateActionsV1` NatSpec for the full external API and integrator
guidance, and `docs/GLOSSARY.md` for domain terms.

## Operational scripts

Scripts under `script/` produce off-chain artifacts (Safe Tx Builder JSON,
signer briefs) and are run manually rather than as part of CI deploys. Each runs
a full on-chain pre-flight, simulates the post-state, emits the artifact, and
logs the canonical hash that signers must verify.

### Convention

- **Flat directory.** Every operational script lives directly under `script/`.
  Scripts are not moved post-execution; their history is captured in the file
  itself.
- **Date-prefixed file name.** Format: `YYYYMMDD-<kebab-name>.s.sol`. The date
  is the day the script was added to the dispatcher dropdown. Chronological sort
  drops out naturally from `ls`.
- **Status in NatSpec.** The file-level NatSpec on each script leads with a
  status banner:
  - Upcoming: `@notice **PENDING.** …`
  - Executed:
    `@notice **EXECUTED YYYY-MM-DD.** … SafeTxHash 0x… landed on
    Base at nonce N. Retained verbatim for retrospective re-verification.`
- **Append-only dispatcher.** `.github/workflows/run-script.yaml` exposes a
  `workflow_dispatch` dropdown that registers every script by its date-prefixed
  name. New scripts are appended to the bottom; entries are never reordered or
  removed (so re-dispatching a historical script remains possible).
- **Adding a new script.** Drop the file under `script/`, append its
  date-prefixed name to the `options:` list in `run-script.yaml`, push.

### Worked example: the multisig threshold migration (executed)

`script/20260619-migrate-multisig-threshold.s.sol` bumped the
`STOX_TOKEN_OWNER_SAFE` threshold from 1-of-6 to 3-of-6 against the
post-rotation 6-owner roster. The bundle landed on Base at nonce 688 with
SafeTxHash `0x30f008fb35c5bfd49386377289ea03a3ff9678c6151795ef9eae014728b8c18f`.

The script's pre-flight asserts, in one call into
`LibSafeInvariants.assertAllChecks`, the pinned Safe v1.4.1 proxy codehash,
singleton + bytecode, version, absence of modules and guard, fallback handler,
uniform `owner()` across every production receipt vault returned by
`LibTokenOwnership.productionReceiptVaults()` (13 vaults), the expected owner
set, and the expected pre-migration threshold (`= 1`). Only after that bundle
passes does it simulate `changeThreshold(3)` via `vm.prank`, re-run the same
bundle against the post-state with the new threshold argument, and emit the Tx
Builder JSON.

Re-derive the artifact (e.g. to retrospectively verify the on-chain bundle
matched what this code emitted):

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/20260619-migrate-multisig-threshold.s.sol --rpc-url base
```

The artifact is written to `out/safe-threshold-migration.json` and the canonical
`SafeTxHash` is logged between explicit `==== TX BUILDER JSON BEGIN ====` /
`==== TX BUILDER JSON END ====` markers so it is greppable from CI logs.

Verify an existing artifact against the live Safe:

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/20260619-migrate-multisig-threshold.s.sol \
  --rpc-url base \
  --sig 'verify(string)' \
  out/safe-threshold-migration.json
```

A successful `verify` exits silently. Any pre-flight or artifact-mismatch
failure surfaces a typed error (`SafeThresholdMismatch`,
`ReceiptVaultOwnerMismatch`, `VerifyMismatch`, etc.) that pinpoints the drift.

The `run-script` GitHub workflow dispatches any registered script on demand
(maintainer-triggered via the Actions UI), uploading `out/*.json` as a build
artifact so signers can download the bundle directly from the run.

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant.
