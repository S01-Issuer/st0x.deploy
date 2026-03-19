# Changelog

## V2 (Zoltu deterministic deployment)

Deployed via Zoltu factory — deterministic addresses identical across all EVM networks (Arbitrum, Base, Base Sepolia, Flare, Polygon).

All contracts have parameterless constructors enabling Zoltu deployment. Constructor dependencies (beacon owner, implementation addresses) are hardcoded from constants.

### Addresses (all networks)

| Contract | Address | Constant |
|---|---|---|
| StoxReceipt | `0xbAB0E6b7B5dDA86FB8ba81c00aEA0Ceb8b73686b` | `LibProdDeployV2.STOX_RECEIPT` |
| StoxReceiptVault | `0xc95dB340A7a100881626475d41BFf70857Aa920D` | `LibProdDeployV2.STOX_RECEIPT_VAULT` |
| StoxWrappedTokenVault | `0xb438a1eA1550fd199d67D67a69B71F4324bB8660` | `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT` |
| StoxWrappedTokenVaultBeacon | `0x846a468e6fDA529D282D60df7D1EE785EB954600` | `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON` |
| StoxWrappedTokenVaultBeaconSetDeployer | `0xBFB3D7Baece65D1f1640986CdA313177F1160C70` | `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` |
| StoxOffchainAssetReceiptVaultBeaconSetDeployer | `0x0C5154C4861908Bd5a6FD6fFCB063e9869ceFa41` | `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` |
| StoxUnifiedDeployer | `0xeaE1c37b7aD1643D20da2B1b97705Fa949eAFaE7` | `LibProdDeployV2.STOX_UNIFIED_DEPLOYER` |
| Beacon owner | `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` | `LibProdDeployV2.BEACON_INITIAL_OWNER` |

### New contracts

- **StoxWrappedTokenVaultBeacon**: Inherits `UpgradeableBeacon` with hardcoded implementation and owner from constants. Replaces the beacon that was previously created inline in the deployer's constructor.
- **StoxOffchainAssetReceiptVaultBeaconSetDeployer**: Inherits upstream `OffchainAssetReceiptVaultBeaconSetDeployer` with hardcoded config from constants. Replaces the upstream deployer that required constructor args.

### StoxWrappedTokenVault

- **Breaking**: Added `ZeroAsset` error and zero-address validation in `initialize(bytes)`. Initializing with `address(0)` now reverts instead of creating a bricked vault.

### StoxWrappedTokenVaultBeaconSetDeployer

- **Breaking**: Removed constructor params (`StoxWrappedTokenVaultBeaconSetDeployerConfig` struct removed). Beacon address is now referenced via `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON`.
- Removed `iStoxWrappedTokenVaultBeacon` immutable (beacon is referenced by constant address).
- Removed `ZeroVaultImplementation` and `ZeroBeaconOwner` errors (validation moved to beacon contract).
- Moved `Deployment` event emit before `initialize` call (checks-effects-interactions).

### StoxReceipt

- No bytecode changes from V1.

### StoxReceiptVault

- No bytecode changes from V1.

### StoxUnifiedDeployer

- **Breaking**: Now references V2 deployer addresses (`LibProdDeployV2`) instead of V1. Vault pairs created through the unified deployer use V2 implementations.

### Deployment infrastructure

- All contracts deploy via `LibRainDeploy.deployAndBroadcast()` with address and codehash verification.
- `Deploy.sol` has one suite per contract, deployed sequentially in dependency order.
- Pointer files in `src/generated/` contain `BYTECODE_HASH`, `DEPLOYED_ADDRESS`, `CREATION_CODE`, and `RUNTIME_CODE` for each contract.
- `--skip-simulation` required for multi-chain broadcast of constructor-dependent contracts.
- Production constants split across `LibProdDeployV1` (Base V1 deployment) and `LibProdDeployV2` (Zoltu deterministic). Each version is fully self-contained.

## V1 (initial Base deployment)

Deployed via `new` in Forge broadcast scripts. Non-deterministic addresses. Base only.

### Addresses (Base)

| Contract | Address | Constant |
|---|---|---|
| OffchainAssetReceiptVaultBeaconSetDeployer | `0x2191981Ca2477B745870cC307cbEB4cB2967ACe3` | `LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` |
| StoxWrappedTokenVaultBeaconSetDeployer | `0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB` | `LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` |
| StoxWrappedTokenVault (implementation) | `0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1` | `LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` |
| StoxUnifiedDeployer | `0x821a71a313bdDDc94192CF0b5F6f5bC31Ac75853` | `LibProdDeployV1.STOX_UNIFIED_DEPLOYER` |
| StoxReceipt (implementation) | `0xE7573879D73455Dc92cB4087Fa8177594387CbCD` | `LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION` |
| StoxReceiptVault (implementation) | `0x8EFfCe5Ebb047F215dF1d8522c32c7C9DE239f39` | `LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION` |
| Beacon owner | `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` | `LibProdDeployV1.BEACON_INITIAL_OWNER` |

### Known issues

- `StoxWrappedTokenVault.initialize(bytes)` accepts `address(0)` as asset without reverting, creating a bricked vault. Fixed in V2.
