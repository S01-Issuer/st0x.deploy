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

### Worked example: the multisig threshold migration

`script/20260619-migrate-multisig-threshold.s.sol` is the first record on the
migration line. Its pre-flight asserts the chain's token-owner Safe is locked
down with the pinned owners and that the record is the line's next. Its bundle
is `changeThreshold(STOX_TOKEN_OWNER_SAFE_THRESHOLD)`, only when the Safe is not
at the pin yet, then the record. The post-state asserts the record and the full
token-owner policy.

Dry-run and produce the artifact:

```shell
forge script script/20260619-migrate-multisig-threshold.s.sol --rpc-url base
```

The artifact is written to
`out/20260619-migrate-multisig-threshold-<chainid>.json` and the bundle's
MultiSend `SafeTxHash` is logged after the `==== TX BUILDER JSON END ====`
marker.

Verify an existing artifact against the live Safe (signers should run this
before signing):

```shell
forge script script/20260619-migrate-multisig-threshold.s.sol \
  --rpc-url base \
  --sig 'verify(string)' \
  out/20260619-migrate-multisig-threshold-8453.json
```

The `multisig-artifact` GitHub workflow runs the dry-run on `workflow_dispatch`
(maintainer-triggered, for producing the bundle the signers actually use) and on
`pull_request` events that touch the migration code or any of its direct
dependencies, uploading `out/*.json` as a build artifact so reviewers can
download the bundle directly from the run.

### Receipt vault V3 upgrade

The receipt vault beacon points at the V3 implementation (corporate actions).
The beacon is owned by the governance timelock, so any further upgrade is a
timelock operation (`docs/TIMELOCK.md`).

The post-upgrade behaviour of live tokens is verified by the shadow-fork suite
`test/src/concrete/upgrade/V3UpgradeShadowFork.t.sol`, which applies the upgrade
to a Base head fork and exercises corporate-action fallback routing,
backwards-compatible reads, authoriser and receipt wiring, and certification
against a real on-chain receipt vault.

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant.
