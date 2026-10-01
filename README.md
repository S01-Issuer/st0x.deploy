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

### Mint weighting

`ST0xOrchestrator` charges its mint-cap buckets with the value a Rainlang
weighting puts on each mint, evaluated over the minter's signed price
attestations (`SPEC.md` of `st0x.attest`, sections 2 and 4). The production
weighting is `src/rain/mint-weighting.rain`, a dotrain source whose elided
bindings are the per-deployment configuration: the `St0xAttestSubParser`
address, the lead signer, the operator allowlist, the tolerances and the price
bounds. Nothing is per token: one composition serves every vault, as the
expression derives the ticker to check attestations against by dropping the `t`
from the symbol of the vault being minted (`tMSTR` to `MSTR`).

Compose it with every binding given, parse the output with the chain's Rainlang
deployer and install the result with `setMintWeighting`:

```
rain dotrain compose -i src/rain/mint-weighting.rain -e weighting \
  -b st0x-attest-subparser=0x… -b lead-signer=0x… \
  -b operator-1=0x… … -b operator-6=0x… \
  -b max-deviation=0.01 -b max-time-spread=600 -b min-price=… -b max-price=…
```

`test/src/rain/MintWeighting.t.sol` composes the same file with the same
substitution and runs it through `mint`, so the checks in the file are the
checks the tests show refusing.

## Operational scripts

Scripts under `script/` that produce off-chain artifacts (Safe Tx Builder JSON,
signer briefs) live alongside the deploy contracts but are run manually rather
than as part of CI deploys. Each runs a full on-chain pre-flight, simulates the
post-state, emits the artifact, and logs the canonical hash that signers must
verify.

### Worked example: the multisig threshold migration

`script/MigrateMultisigThreshold.s.sol` bumps the `STOX_TOKEN_OWNER_SAFE`
threshold from 1-of-4 to 3-of-4 against the current 4-owner roster. The script's
pre-flight asserts, in one call into `LibSafeInvariants.assertAllChecks`, the
pinned Safe v1.4.1 proxy codehash, singleton + bytecode, version, absence of
modules and guard, fallback handler, uniform `owner()` across every production
receipt vault returned by `LibTokenOwnership.productionReceiptVaults()` (13
vaults), the expected owner set, and the expected pre-migration threshold
(`= 1`). Only after that bundle passes does it simulate `changeThreshold(3)` via
`vm.prank`, re-run the same bundle against the post-state with the new threshold
argument, and emit the Tx Builder JSON.

Dry-run and produce the artifact:

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/MigrateMultisigThreshold.s.sol --rpc-url base
```

The artifact is written to `out/safe-threshold-migration.json` and the canonical
`SafeTxHash` is logged between explicit `==== TX BUILDER JSON BEGIN ====` /
`==== TX BUILDER JSON END ====` markers so it is greppable from CI logs.

Verify an existing artifact against the live Safe (signers should run this
before signing):

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/MigrateMultisigThreshold.s.sol \
  --rpc-url base \
  --sig 'verify(string)' \
  out/safe-threshold-migration.json
```

A successful `verify` exits silently. Any pre-flight or artifact-mismatch
failure surfaces a typed error (`SafeThresholdMismatch`,
`ReceiptVaultOwnerMismatch`, `VerifyMismatch`, etc.) that pinpoints the drift.

The `multisig-artifact` GitHub workflow runs the dry-run on `workflow_dispatch`
(maintainer-triggered, for producing the bundle the signers actually use) and on
`pull_request` events that touch the migration code or any of its direct
dependencies, uploading `out/*.json` as a build artifact so reviewers can
download the bundle directly from the run.

### Receipt vault V3 upgrade

`script/UpgradeReceiptVaultToV3.s.sol` authors the Safe transaction that points
`STOX_RECEIPT_VAULT_BEACON_V1` at the V3 receipt vault implementation (corporate
actions). After execution every live receipt vault routes corporate-action
selectors into the V3 facet via fallback delegatecall. The beacon must already
be Safe-owned (run the beacon ownership migration first) and the V3
implementation must already be deployed at its deterministic Zoltu address with
the audited codehash. The script runs `assertAll(safe)` +
`assertBeaconInvariants(beacon, safe, V1 impl)` as pre-flight, simulates the
`upgradeTo`, asserts the post-state (`beacon -> V3 impl`, Safe unchanged), emits
the Tx Builder JSON to `out/v3-upgrade.json`, prints the `SafeTxHash`, and
proves n+1 reversibility back to the V1 implementation.

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/UpgradeReceiptVaultToV3.s.sol --rpc-url base
```

The post-upgrade behaviour of live tokens is verified by the shadow-fork suite
`test/src/concrete/upgrade/V3UpgradeShadowFork.t.sol`, which applies the upgrade
to a Base head fork and exercises corporate-action fallback routing,
backwards-compatible reads, authoriser and receipt wiring, and certification
against a real on-chain receipt vault.

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant.
