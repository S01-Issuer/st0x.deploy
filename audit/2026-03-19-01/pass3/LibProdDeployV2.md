# Pass 3 (Documentation) — LibProdDeployV2.sol

**Agent:** A11
**File:** `src/lib/LibProdDeployV2.sol` (81 lines)

## Evidence of Thorough Reading

**Library name:** `LibProdDeployV2` (line 38)

**Functions:** None — constants-only library.

**Errors/Types:** None defined.

**Imports (7 generated pointer files, lines 5-32):**

| Pointer File | Imported Symbols (aliased) | Lines |
|---|---|---|
| `StoxReceipt.pointers.sol` | `BYTECODE_HASH` as `STOX_RECEIPT_HASH`, `DEPLOYED_ADDRESS` as `STOX_RECEIPT_ADDR` | 5-8 |
| `StoxReceiptVault.pointers.sol` | `BYTECODE_HASH` as `STOX_RECEIPT_VAULT_HASH`, `DEPLOYED_ADDRESS` as `STOX_RECEIPT_VAULT_ADDR` | 9-12 |
| `StoxWrappedTokenVault.pointers.sol` | `BYTECODE_HASH` as `STOX_WRAPPED_TOKEN_VAULT_HASH`, `DEPLOYED_ADDRESS` as `STOX_WRAPPED_TOKEN_VAULT_ADDR` | 13-16 |
| `StoxUnifiedDeployer.pointers.sol` | `BYTECODE_HASH` as `STOX_UNIFIED_DEPLOYER_HASH`, `DEPLOYED_ADDRESS` as `STOX_UNIFIED_DEPLOYER_ADDR` | 17-20 |
| `StoxWrappedTokenVaultBeacon.pointers.sol` | `BYTECODE_HASH` as `STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH`, `DEPLOYED_ADDRESS` as `STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR` | 21-24 |
| `StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol` | `BYTECODE_HASH` as `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH`, `DEPLOYED_ADDRESS` as `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR` | 25-28 |
| `StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol` | `BYTECODE_HASH` as `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_HASH`, `DEPLOYED_ADDRESS` as `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_ADDR` | 29-32 |

**Constants defined (15 total):**

| Type | Name | Line(s) | Value Source |
|------|------|---------|--------------|
| `address` | `BEACON_INITIAL_OWNER` | 42 | Hardcoded `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` |
| `address` | `STOX_RECEIPT` | 45 | `STOX_RECEIPT_ADDR` from pointer |
| `bytes32` | `STOX_RECEIPT_CODEHASH` | 47 | `STOX_RECEIPT_HASH` from pointer |
| `address` | `STOX_RECEIPT_VAULT` | 50 | `STOX_RECEIPT_VAULT_ADDR` from pointer |
| `bytes32` | `STOX_RECEIPT_VAULT_CODEHASH` | 52 | `STOX_RECEIPT_VAULT_HASH` from pointer |
| `address` | `STOX_WRAPPED_TOKEN_VAULT` | 55 | `STOX_WRAPPED_TOKEN_VAULT_ADDR` from pointer |
| `bytes32` | `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` | 57 | `STOX_WRAPPED_TOKEN_VAULT_HASH` from pointer |
| `address` | `STOX_UNIFIED_DEPLOYER` | 60 | `STOX_UNIFIED_DEPLOYER_ADDR` from pointer |
| `bytes32` | `STOX_UNIFIED_DEPLOYER_CODEHASH` | 62 | `STOX_UNIFIED_DEPLOYER_HASH` from pointer |
| `address` | `STOX_WRAPPED_TOKEN_VAULT_BEACON` | 65 | `STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR` from pointer |
| `bytes32` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH` | 67 | `STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH` from pointer |
| `address` | `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 70-71 | `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_ADDR` from pointer |
| `bytes32` | `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH` | 73-74 | `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_HASH` from pointer |
| `address` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 77 | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR` from pointer |
| `bytes32` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH` | 79-80 | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH` from pointer |

---

## Documentation Review

### Library-level NatSpec (lines 34-37)

```solidity
/// @title LibProdDeployV2
/// @notice V2 production deployment addresses and codehashes for the Stox
/// deployment via the Zoltu deterministic deployer. Addresses are
/// deterministic and identical across all EVM networks.
```

Both `@title` and `@notice` are present and accurate. The notice correctly identifies the V2-specific characteristic (Zoltu deterministic deployer, cross-chain address identity). No inaccuracy.

### Per-constant NatSpec — Pointer-derived constants (lines 44-80)

All 14 pointer-derived constants (7 address + 7 codehash) have `/// @dev` comments following a consistent pattern:
- Address constants: `"Deterministic Zoltu address for <ContractName>."`
- Codehash constants: `"Codehash of <ContractName> when deployed via Zoltu."`

The naming in these comments matches the actual contract names in every case. No stale or misleading text.

### BEACON_INITIAL_OWNER NatSpec (lines 39-41)

```solidity
/// @dev The initial owner for beacon set deployers. Resolves to
/// rainlang.eth.
/// https://basescan.org/address/0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b
```

The comment states "The initial owner for beacon set deployers." However, this constant is used in two different contexts:

1. `StoxWrappedTokenVaultBeacon.sol` (line 12) — as the `initialOwner` parameter of `UpgradeableBeacon`. This is a standalone beacon, NOT a beacon set deployer.
2. `StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol` (line 17) — as `initialOwner` in the beacon set deployer config.

The `StoxOffchainAssetReceiptVaultBeaconSetDeployer` internally creates beacons that also use this owner. So the constant is the initial owner for ALL beacons in the V2 deployment — both the standalone beacon and those created by the beacon set deployer. The current NatSpec is incomplete because it only mentions "beacon set deployers" and omits the standalone beacon use case.

### Basescan URL accuracy

The Basescan URL on line 41 (`https://basescan.org/address/0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b`) matches the hardcoded address literal on line 42. The link is consistent with the address.

### V1 vs V2 documentation consistency

V1 (`LibProdDeployV1`) provides Basescan URLs for every address constant. V2 omits them for all pointer-derived constants. This is reasonable and expected because V2 addresses are network-agnostic (Zoltu deterministic deployment), so a single-chain explorer link would be incomplete. Only `BEACON_INITIAL_OWNER` (which is a person/multisig address, not a Zoltu-deployed contract) retains a Basescan link. This is consistent and intentional.

### Stale references

None found. All documentation accurately reflects the current state of the file.

---

## Findings

### A11-P3-1: `BEACON_INITIAL_OWNER` NatSpec understates usage scope [LOW]

**Severity:** LOW

**Location:** `src/lib/LibProdDeployV2.sol`, lines 39-40

**Description:**

The `@dev` comment for `BEACON_INITIAL_OWNER` reads: "The initial owner for beacon set deployers." This is incomplete. The constant is used as the initial owner for:

1. `StoxWrappedTokenVaultBeacon` (standalone `UpgradeableBeacon`, line 12 of `StoxWrappedTokenVaultBeacon.sol`)
2. `StoxOffchainAssetReceiptVaultBeaconSetDeployer` (beacon set deployer, which internally creates beacons with this owner)

The current wording implies the constant only applies to beacon set deployers, but it is also the owner of the standalone wrapped token vault beacon. A reader consulting this library to understand beacon ownership would get an incomplete picture.

**Impact:** A developer or auditor reading the NatSpec could incorrectly conclude that `BEACON_INITIAL_OWNER` is only relevant to beacon set deployers and overlook its role as the owner of `StoxWrappedTokenVaultBeacon`. This could lead to confusion during ownership audits or upgrade governance analysis.

**Fix:** Update the `@dev` comment to accurately describe all usage. See `.fixes/A11-P3-1.md`.

---

_No other findings. The library-level `@title` and `@notice` are present and accurate. All 14 pointer-derived constants have correct, uniform `@dev` comments. The Basescan URL on `BEACON_INITIAL_OWNER` matches the hardcoded address. The omission of explorer links on Zoltu-derived constants is consistent with their network-agnostic nature._
