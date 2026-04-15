# st0x.deploy

Deployment and extension contracts for [rain.vats](https://github.com/rainlanguage/rain.vats) that are domain-specific for st0x. Implements RWA tokenization with receipt vaults wrapped in ERC4626-compatible vaults for DeFi integration.

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
               │ uses
    ┌──────────┴───────────────────────────────────────────┐
    │                    src/lib/                            │
    │  LibCorporateAction    — doubly linked list + storage │
    │  LibCorporateActionNode — traversal with filters      │
    │  LibStockSplit         — validation + decode          │
    │  LibRebase             — share-side lazy migration    │
    │  LibReceiptRebase      — receipt-side lazy migration  │
    │  LibRebaseMath         — shared multiplier primitive  │
    │  LibTotalSupply        — per-cursor pot accounting    │
    │  LibERC20Storage       — direct OZ ERC20 slot access  │
    │  LibERC1155Storage     — direct OZ ERC1155 slot access│
    │  LibCorporateActionReceipt — receipt cursor storage   │
    └──────────────────────────────────────────────────────┘
```

### Token Topology (per deposit)

| Contract | Standard | Purpose |
|----------|----------|---------|
| `StoxReceipt` | ERC-1155 | Proof of deposit, receipt-id granularity |
| `StoxReceiptVault` | ERC-20 | Fungible vault shares, rebase-aware |
| `StoxWrappedTokenVault` | ERC-4626 | Wraps shares, captures rebases in price |

### Corporate Actions

The corporate actions system adds stock split support via a diamond facet that is delegatecalled by the vault. Key design choices:

- **No stored status** — an action is complete when `effectiveTime <= block.timestamp`
- **Lazy migration** — balances rasterize on first interaction after a split
- **Sequential precision** — each multiplier truncates independently (no cumulative product)
- **Per-cursor pots** — `totalSupply` improves precision as accounts migrate

See `CORPORATE-ACTIONS-SPEC.md` for the full specification and `docs/INTEGRATION.md` for external consumer guidance.

### Directory Structure

- `src/concrete/` — StoxReceipt, StoxReceiptVault, StoxWrappedTokenVault, StoxCorporateActionsFacet
- `src/concrete/authorize/` — Authorizer implementations
- `src/concrete/deploy/` — Deployer contracts (unified deployer, beacon set deployers)
- `src/interface/` — `ICorporateActionsV1` versioned interface
- `src/lib/` — Libraries (corporate actions, rebase, storage access, production addresses)
- `src/generated/` — Zoltu deterministic deployment pointer files
- `script/` — Forge deployment scripts
- `test/` — Foundry tests (unit, fuzz, invariant, fork)
- `audit/` — Audit findings and triage decisions
- `docs/` — Integration guide for external consumers
- `lib/` — Git submodule dependencies (rain.vats, rain.deploy, rain.extrospection)

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant.
