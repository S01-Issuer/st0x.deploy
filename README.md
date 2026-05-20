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

Scripts under `script/` that produce off-chain artifacts (Safe Tx Builder JSON,
signer briefs) live alongside the deploy contracts but are run manually rather
than as part of CI deploys. Each runs a full on-chain pre-flight, simulates the
post-state, emits the artifact, and logs the canonical hash that signers must
verify.

### RAI-296 — Safe threshold 1-of-4 → 3-of-4

`script/MigrateMultisigThreshold.s.sol` bumps the `STOX_TOKEN_OWNER_SAFE`
threshold against the current 4-owner roster. The script's pre-flight asserts
the pinned Safe v1.4.1 proxy codehash, singleton, version, owner set, threshold
(`= 1`), absence of modules and guard, and uniform `owner()` across every
receipt vault returned by `LibTokenOwnership.allReceiptVaults()` (13
production + 1 legacy NVDA). Only after those pass does it simulate
`changeThreshold(3)` via `vm.prank` and emit the Tx Builder JSON.

Dry-run and produce the artifact:

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/MigrateMultisigThreshold.s.sol --rpc-url base
```

The artifact is written to `out/rai-296-threshold-migration.json` and the
canonical `SafeTxHash` is logged between explicit
`==== TX BUILDER
JSON BEGIN ====` / `==== TX BUILDER JSON END ====` markers so
it is greppable from CI logs.

Verify an existing artifact against the live Safe (signers should run this
before signing):

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/MigrateMultisigThreshold.s.sol \
  --rpc-url base \
  --sig 'verify(string)' \
  out/rai-296-threshold-migration.json
```

A successful `verify` exits silently. Any pre-flight or artifact- mismatch
failure surfaces a typed error (`SafeThresholdMismatch`,
`ReceiptVaultOwnerMismatch`, `VerifyMismatch`, etc.) that pinpoints the drift.

The `multisig-artifact` GitHub workflow runs the dry-run on every push to a
`feat/rai-296-*` branch and uploads `out/*.json` as a build artifact so
reviewers can download the bundle directly from the PR.

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant.
