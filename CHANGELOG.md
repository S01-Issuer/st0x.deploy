# Changelog

## V2 (Zoltu deterministic deployment)

Deployed via Zoltu factory — deterministic addresses across all EVM networks.

### StoxWrappedTokenVault

- **Breaking**: Added `ZeroAsset` error and zero-address validation in `initialize(bytes)`. Initializing with `address(0)` now reverts instead of creating a bricked vault.

### StoxWrappedTokenVaultBeaconSetDeployer

- Renamed immutable `I_STOX_WRAPPED_TOKEN_VAULT_BEACON` to `iStoxWrappedTokenVaultBeacon` (mixedCase convention).
- Moved `Deployment` event emit before `initialize` call (checks-effects-interactions).

### StoxReceipt

- No changes from V1.

### StoxReceiptVault

- No changes from V1.

### StoxUnifiedDeployer

- No changes from V1.

## V1 (initial Base deployment)

Deployed via `new` in Forge broadcast scripts. Non-deterministic addresses.

### Addresses (Base)

| Contract | Address |
|---|---|
| OffchainAssetReceiptVaultBeaconSetDeployer | `0x2191981Ca2477B745870cC307cbEB4cB2967ACe3` |
| StoxWrappedTokenVaultBeaconSetDeployer | `0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB` |
| StoxWrappedTokenVault (implementation) | `0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1` |
| StoxUnifiedDeployer | `0x821a71a313bdDDc94192CF0b5F6f5bC31Ac75853` |
| StoxReceipt (implementation) | `0xE7573879D73455Dc92cB4087Fa8177594387CbCD` |
| StoxReceiptVault (implementation) | `0x8EFfCe5Ebb047F215dF1d8522c32c7C9DE239f39` |
| Beacon owner | `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` (rainlang.eth) |

### Known issues

- `StoxWrappedTokenVault.initialize(bytes)` accepts `address(0)` as asset without reverting, creating a bricked vault. Fixed in V2.
