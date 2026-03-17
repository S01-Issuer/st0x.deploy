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
- `StoxWrappedTokenVaultBeaconSetDeployer` — manages an `UpgradeableBeacon` for wrapped vault proxies
- `StoxUnifiedDeployer` — atomically deploys a receipt vault + wrapped vault pair using hardcoded beacon deployer addresses from `LibProdDeploy`

**ICloneableV2 pattern** (from rain.factory): contracts have dual `initialize` overloads — `initialize(address)` always reverts (documents signature), `initialize(bytes)` is the real initializer returning `ICLONEABLE_V2_SUCCESS`.

**Production addresses** are hardcoded in `LibProdDeploy` with Basescan links. Codehash constants are verified by fork tests against live Base deployments.

## Dependencies

Git submodules managed via Foundry. Key remappings in `foundry.toml`:
- `ethgild/` → receipt vault framework
- `rain.factory/` → clonable factory pattern (ICloneableV2)
- `openzeppelin-contracts-upgradeable/` → ERC4626, ERC20, beacon proxies

## Compiler Settings

- Solidity 0.8.25 (exact pin `=0.8.25` in contracts, `^0.8.25` in libraries)
- EVM target: Cancun
- Optimizer: 100,000 runs
- `bytecode_hash = "none"`, `cbor_metadata = false` — enables deterministic codehash comparison in fork tests

## Deployment

`script/Deploy.sol` dispatches based on `DEPLOYMENT_SUITE` env var:
- `offchain-asset-receipt-vault-beacon-set` — deploys receipt + receipt vault beacon set
- `wrapped-token-vault-beacon-set` — deploys wrapped vault beacon set
- `unified-deployer` — deploys the unified deployer

Manual deployment via GitHub Actions workflow (`manual-sol-artifacts.yaml`) supports multiple networks.

## License

LicenseRef-DCL-1.0 (DecentraLicense). REUSE-compliant — run `rainix-sol-legal` to validate.
