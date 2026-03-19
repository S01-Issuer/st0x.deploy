# Pass 5: Correctness / Intent Verification -- `src/concrete/StoxReceiptVault.sol`

**Agent:** A04
**Date:** 2026-03-19
**File:** `src/concrete/StoxReceiptVault.sol` (11 lines)

---

## Evidence of Thorough Reading

### Contract

| Name | Line | Base |
|---|---|---|
| `StoxReceiptVault` | 11 | `OffchainAssetReceiptVault` (ethgild) |

### Imports

| Symbol | Source | Line |
|---|---|---|
| `OffchainAssetReceiptVault` | `ethgild/concrete/vault/OffchainAssetReceiptVault.sol` | 5 |

### Functions defined in this file

None. The contract body is empty (`{}`).

### Types / Errors / Constants defined in this file

None.

### Inherited public/external interface (from `OffchainAssetReceiptVault`)

Key functions inherited from `OffchainAssetReceiptVault` and its ancestors:

| Function | Visibility | OARV Line |
|---|---|---|
| `initialize(bytes)` | public virtual | 301 |
| `highwaterId()` | external view | 331 |
| `supportsInterface(bytes4)` | public view virtual | 337 |
| `authorizer()` | external view | 342 |
| `authorize(address,bytes32,bytes)` | external view virtual | 351 |
| `setAuthorizer(IAuthorizeV1)` | external | 372 |
| `authorizeReceiptTransfer3(...)` | public virtual | 378 |
| `totalAssets()` | public view virtual | 478 |
| `redeposit(uint256,address,uint256,bytes)` | external | 516 |
| `certify(uint256,bool,bytes)` | external | 582 |
| `isCertificationExpired()` | public view | 608 |
| `confiscateShares(address,uint256,bytes)` | external | 666 |
| `confiscateReceipt(address,uint256,uint256,bytes)` | external | 718 |

Plus all ReceiptVault, ERC20Upgradeable, ERC4626-like, OwnableUpgradeable, and OwnerFreezable public functions.

---

## Correctness Verification

### 1. Contract name vs behavior

The contract is named `StoxReceiptVault` and the NatSpec says: "An OffchainAssetReceiptVault specialized for StoxReceipts. Currently there are no modifications to the base contract, but this is here to prepare for any future upgrades."

**Verified:** The body is empty. All behavior delegates to `OffchainAssetReceiptVault`. The name accurately conveys that this is a Stox-specific OffchainAssetReceiptVault that can diverge from the base in future versions.

### 2. NatSpec accuracy

The `@notice` makes two claims:
1. "An OffchainAssetReceiptVault specialized for StoxReceipts" -- Correct. Inherits `OffchainAssetReceiptVault`.
2. "Currently there are no modifications to the base contract" -- Correct. Empty body.
3. "here to prepare for any future upgrades" -- Correct design rationale for having a distinct type.

**Note:** Unlike sibling `StoxReceipt`, this contract lacks a `@dev` tag documenting the ICloneableV2 initialization encoding. This was identified in Pass 3 as A04-P3-3 (LOW). Not a correctness issue, but a documentation inconsistency.

### 3. Constructor behavior

`OffchainAssetReceiptVault` inherits from `ReceiptVault`, which should call `_disableInitializers()` in its constructor. Let me verify the chain:

`OffchainAssetReceiptVault` does not define its own constructor; it relies on `ReceiptVault`'s constructor. `ReceiptVault` inherits from `ERC20Upgradeable` (OpenZeppelin upgradeable), which has a default constructor that does nothing explicit -- but importantly, `OffchainAssetReceiptVault` uses the `initializer` modifier on `initialize(bytes)` which is the standard OZ upgradeable pattern.

Examining the constructor chain: The `OffchainAssetReceiptVault.initialize` function (L301) has the `initializer` modifier. The implementation contract deployed via Zoltu will have `_disableInitializers()` called if the constructor invokes it. Checking the ethgild ReceiptVault base -- since `StoxReceiptVault` has no explicit constructor, the default constructor of `OffchainAssetReceiptVault` runs. The OZ upgradeable pattern typically has the constructor call `_disableInitializers()`.

**Test coverage:** `test/src/concrete/StoxReceiptVault.t.sol:testConstructorDisablesInitializers` creates a `StoxReceiptVault` and verifies that `initialize(abi.encode(address(1)))` reverts with `Initializable.InvalidInitialization`. This confirms the constructor does disable initializers.

### 4. Initialize encoding

The inherited `initialize(bytes)` function (OARV L301) expects `abi.decode(data, (OffchainAssetReceiptVaultConfigV2))`. This config struct contains:
- `initialAdmin` (address) -- must be non-zero
- `receiptVaultConfig` (ReceiptVaultConfigV2) -- must have `asset == address(0)` for offchain vaults

The initialization:
1. Calls `__ReceiptVault_init(config.receiptVaultConfig)` (L304)
2. Validates `asset == address(0)` (L307-309) -- reverts `NonZeroAsset` otherwise
3. Validates `initialAdmin != address(0)` (L311-313) -- reverts `ZeroInitialAdmin` otherwise
4. Sets authorizer to self (L315) -- the self-authorizer always reverts, requiring owner to set a real one
5. Transfers ownership to `initialAdmin` (L317)
6. Emits `OffchainAssetReceiptVaultInitializedV2` (L319-325)
7. Returns `ICLONEABLE_V2_SUCCESS` (L327)

**Verified:** All initialization logic is correct and consistent with the contract's documented purpose.

### 5. Interface conformance

`StoxReceiptVault` inherits from `OffchainAssetReceiptVault`, which implements:
- `IAuthorizeV1` (authorize function, supportsInterface check)
- `ReceiptVault` (ERC4626-like vault interface)
- `OwnerFreezable` (freeze/unfreeze functionality)
- `ICloneableV2` (initialize pattern)

Since StoxReceiptVault adds no overrides, it conforms identically to all inherited interfaces.

**Verified:** No interface violations possible in an empty-body subcontract.

### 6. Solidity version

`pragma solidity =0.8.25` -- exact pin for a concrete contract. Matches project convention.

### 7. Deployment correctness

`StoxReceiptVault` has a parameterless constructor (inherited behavior calls `_disableInitializers()`), making it Zoltu-deployable. `Deploy.sol` correctly passes `type(StoxReceiptVault).creationCode` with `noDeps`.

The `StoxOffchainAssetReceiptVaultBeaconSetDeployer` uses `StoxReceiptVault` as the vault implementation for its beacon. This is correct -- the deployer's constructor receives the implementation address and creates an `UpgradeableBeacon` pointing to it.

### 8. Test coverage assessment

Current tests in `test/src/concrete/StoxReceiptVault.t.sol`:
- `testConstructorDisablesInitializers` -- verifies implementation cannot be reinitialized.

Previously proposed additional tests (`.fixes/A04-3.md`) cover initialize happy path, error paths (NonZeroAsset, ZeroInitialAdmin), double-initialize guard, highwaterId, certification, authorizer, setAuthorizer, and supportsInterface. These are not yet implemented but were proposed in a prior pass.

Fork tests in `test/src/lib/LibProdDeployV2.t.sol` verify that the deployed on-chain `StoxReceiptVault` has the expected address and codehash, providing indirect deployment correctness verification.

---

## Findings

No new findings. The contract is an empty-body specialization of `OffchainAssetReceiptVault` with:
- Accurate NatSpec describing purpose and inheritance (though missing `@dev` for init encoding -- tracked as A04-P3-3 from Pass 3).
- Correct constructor behavior (inherited `_disableInitializers()`, test-verified).
- Correct interface conformance.
- Consistent Solidity version.

Previously identified findings from other passes remain applicable:
- A04-P3-3 (LOW, Pass 3): Missing `@dev` tag for ICloneableV2 initialization encoding.
- A04-3 (LOW, Pass 1): Proposed expanded behavioral test coverage -- not yet implemented.

---

## Summary

| Check | Result |
|---|---|
| Contract name matches intent | Correct |
| NatSpec claims verified | Accurate (missing @dev noted in prior pass) |
| Constructor behavior | Correct (inherits _disableInitializers, test-verified) |
| Initialize encoding | Correct (OffchainAssetReceiptVaultConfigV2) |
| Interface conformance | Correct (IAuthorizeV1, ICloneableV2, ReceiptVault, OwnerFreezable) |
| Solidity version | Correct (=0.8.25) |
| Deployment correctness | Correct (Zoltu-deployable, noDeps) |
| Test coverage | Minimal but correct; expanded tests proposed in prior pass |
| Findings | 0 new |
