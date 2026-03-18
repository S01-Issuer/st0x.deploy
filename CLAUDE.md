# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

st0x.deploy is a Solidity project that extends [Ethgild](https://github.com/rainlanguage/ethgild) with domain-specific deployment and vault contracts for the Stox protocol. It implements RWA tokenization using receipt vaults wrapped in ERC4626-compatible vaults for DeFi integration.

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

# CI commands (via rainix)
nix develop -c rainix-sol-test       # Full test suite
nix develop -c rainix-sol-static     # Static analysis
nix develop -c rainix-sol-legal      # REUSE license compliance
```

Fork tests require `RPC_URL_BASE_FORK` env var (set in `.env`). They validate deployed contract codehashes against Base mainnet at a pinned block.

## Architecture

**Beacon Proxy + ERC4626 Vault Pattern:**
- `StoxReceiptVault` (extends ethgild's `OffchainAssetReceiptVault`) — receipt-based RWA vault with ERC1155 receipts
- `StoxWrappedTokenVault` (ERC4626 + ICloneableV2) — wraps the receipt vault, capturing rebases/dividends in price rather than supply
- `StoxWrappedTokenVaultBeacon` — `UpgradeableBeacon` with hardcoded implementation and owner from constants
- `StoxWrappedTokenVaultBeaconSetDeployer` — creates beacon proxy instances, references beacon by Zoltu address
- `StoxOffchainAssetReceiptVaultBeaconSetDeployer` — inherits upstream deployer with hardcoded config
- `StoxUnifiedDeployer` — atomically deploys a receipt vault + wrapped vault pair

**ICloneableV2 pattern** (from rain.factory): contracts have dual `initialize` overloads — `initialize(address)` always reverts (documents signature), `initialize(bytes)` is the real initializer returning `ICLONEABLE_V2_SUCCESS`.

**Zoltu deterministic deployment**: All contracts have parameterless constructors enabling deployment via the Zoltu factory for identical addresses across all EVM networks. Pointer files in `src/generated/` contain deterministic addresses and bytecodes.

**Production constants** are split by version:
- `LibProdDeploy` — version-independent (beacon owner)
- `LibProdDeployV1` — V1 Base deployment addresses, codehashes, creation bytecodes
- `LibProdDeployV2` — V2 Zoltu addresses and codehashes from generated pointers

## Dependencies

Git submodules managed via Foundry. Key remappings in `foundry.toml`:
- `ethgild/` → receipt vault framework
- `rain.factory/` → clonable factory pattern (ICloneableV2)
- `rain.deploy/` → Zoltu deterministic deployment
- `rain.sol.codegen/` → pointer file generation
- `openzeppelin-contracts-upgradeable/` → ERC4626, ERC20, beacon proxies

## Compiler Settings

- Solidity 0.8.25 (exact pin `=0.8.25` in contracts, `^0.8.25` in libraries)
- EVM target: Cancun
- Optimizer: 100,000 runs
- `bytecode_hash = "none"`, `cbor_metadata = false` — enables deterministic codehash comparison in fork tests

## Versioning

Production deployments are versioned (`LibProdDeployV1`, `LibProdDeployV2`, etc.). Each version has its own constants file and may have a separate deploy library. When making changes to contract source:
- Update `CHANGELOG.md` with the change under the current version heading
- Regenerate pointer files if creation bytecodes change (`forge script script/BuildPointers.sol`)

## Deployment

`script/Deploy.sol` dispatches based on `DEPLOYMENT_SUITE` env var:
- `offchain-asset-receipt-vault-beacon-set` — deploys receipt + receipt vault beacon set
- `wrapped-token-vault-beacon-set` — deploys wrapped vault beacon set
- `unified-deployer` — deploys the unified deployer

Manual deployment via GitHub Actions workflow (`manual-sol-artifacts.yaml`) supports multiple networks.

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant — run `rainix-sol-legal` to validate.
