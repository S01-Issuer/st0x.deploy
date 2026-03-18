# st0x.deploy

Deployment and extension contracts for [Ethgild](https://github.com/rainlanguage/ethgild) that are domain-specific for st0x. Implements RWA tokenization with receipt vaults wrapped in ERC4626-compatible vaults for DeFi integration.

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

- `src/concrete/` — StoxReceipt, StoxReceiptVault, StoxWrappedTokenVault
- `src/concrete/deploy/` — Deployer contracts (unified deployer, beacon set deployer)
- `src/lib/` — Production deployment addresses and codehashes
- `script/` — Forge deployment scripts
- `test/` — Foundry tests (unit + Base fork)
- `lib/` — Git submodule dependencies (ethgild, rain.extrospection)
