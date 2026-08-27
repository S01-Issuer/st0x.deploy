# Changelog

## V4 (rain.vats 0.1.6)

### StoxReceiptVault

- **Fix (audit H01): keep OZ's `_totalSupply` in step with rebased balances.**
  `migrateAccount` rewrites `_balances` directly via `LibERC20Storage`, so
  before this change OZ's own `_totalSupply` accumulator was never adjusted for
  a stock split and drifted below the true balance sum. OZ subtracts from that
  accumulator **unchecked** on burn and adds to it **checked** on mint, so the
  first burn exceeding the stale value wrapped the slot to ~`2**256` and every
  subsequent mint reverted with `Panic(0x11)` — permanently capping issuance,
  with no external symptom because `totalSupply()`, `balanceOf()` and all events
  stayed mutually consistent. The slot has no write path other than mint/burn,
  so recovery would have required a beacon implementation upgrade.
  `migrateAccount` now applies the balance delta to the raw slot as well, via
  the new `LibERC20Storage.applyBalanceDeltaToTotalSupply`. Reported supply is
  unchanged: `totalSupply()` remains `LibTotalSupply.effectiveTotalSupply()` and
  the per-cursor pot accounting is untouched. Reported by Protofire as H01 in
  the `st0x.deploy 5.0` report (July 2026, audited at `ed767bf2`).

- **`optimizer_runs` lowered 5000 → 2000 to fit the H01 fix under EIP-170.**
  `StoxReceiptVault` had only a 6-byte runtime margin (24,570 of 24,576) at 5000
  runs, and the smallest correct form of the H01 fix costs ~148 bytes. Measured
  with the fix applied: `runs=5000` → 24,718 (over by 142); `runs=3000` →
  24,456; `runs=2000` → 24,037 (**539 spare**); `runs=1000` → 22,936. Two
  in-vault alternatives were measured and rejected: hoisting the supply sync to
  a single call site in `_update` costs _more_ than the duplicated inline
  (24,809), and `unchecked` arithmetic recovers only 18 bytes (24,700).

  This changes the compiled bytecode — and therefore the deterministic Zoltu
  address — of **every** contract, not just the vault. Consequences:

  - No user-facing address moves. Every per-token contract is a `BeaconProxy`,
    so token addresses, beacon addresses and roles are all unaffected.
  - ⚠️ **This is a coordinated multi-contract release, not a single vault
    upgrade.** Three singletons must be deployed and pointed at in lockstep:
    - `StoxReceiptVault` — the H01 fix itself; requires the vault beacon to be
      repointed.
    - `StoxCorporateActionsFacet` — the vault bakes
      `LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET` into its `fallback()`.
      That address moved, so a vault built from this source delegatecalls into
      empty code until the facet is deployed at its new address. This coupling
      was previously invisible because the facet's bytecode had been unchanged
      since 0.1.1, making the candidate and 0.1.1 addresses coincide.
    - `StoxReceipt` — `ST0xOrchestrator`'s vault-logic version lock compares the
      live vault and receipt beacon implementations against
      `LibProdDeployCurrent`. The receipt's address moved even though its source
      did not, so the orchestrator halts mint/burn until a new receipt
      implementation is deployed and its beacon repointed.

    Only the first of these is required by the H01 fix; the other two are
    consequences of the optimizer change.
  - The `testDeployAddress*` assertions for `StoxReceipt`,
    `StoxWrappedTokenVault`, `StoxWrappedTokenVaultBeacon` and both authorizers
    are re-pointed from the frozen `_0_1_1` pins to `_CANDIDATE`, matching what
    `StoxReceiptVault` already did. `0_1_1` stays as the frozen historical
    record of what is live on Base; `testFrozenRedeploy*` keeps proving those
    snapshots redeploy reproducibly, independent of the current optimizer
    setting, and the on-chain fork codehash tests still compare live code to the
    unchanged `0_1_1` pins.
  - The property given up is "a fresh build of current source reproduces the
    _previously released_ artifacts". Verifying those against the repo now means
    using the frozen snapshot rather than a fresh build. Deploying the stack to
    a **new chain** must likewise use the frozen creation code to keep addresses
    identical to Base.
  - Runtime gas rises across all contracts. `.gas-snapshot` is stale as a
    result; it is not gate-checked by CI (`rainix-sol-test` is just
    `forge test -vvv`) and should be regenerated in CI, where the fork-test RPC
    secrets are available.

### Deploy scripts

- **The per-chain "deploy missing tokens" scripts are merged into one.**
  `20260722-deploy-missing-tokens-ethereum` and `-hyperevm` were byte-identical
  apart from the chain each hardcoded; both are replaced by
  `20260807-deploy-missing-tokens`, which resolves the target chain's token
  table, authoriser and Safe from `block.chainid`. Adding a target chain is now
  a table plus an authoriser pin rather than a new copy of the script.
- **"Missing" is now defined against Base, not against the canonical config.** A
  token is missing when its `underlying` appears in `productionTokensBase()` and
  not in the target chain's table, matched by key rather than by index. Base is
  the source of truth for what the token set is — a ticker is deployed there
  first, pinned, then copied outward — so the target chain's table simply lags
  Base until the script runs. Matching by key is what lets the two tables carry
  different lengths in that window; the previous index-join required every table
  to be the same length at all times. Cross-chain parity is red between the Base
  pin and the copy, which is accurate: the chains genuinely differ until the
  copy lands.
- Dispatching the script against Base, or any chain without a token table,
  reverts `UnsupportedTargetChain` rather than resolving to an empty table and
  reading as "copy everything".
- **The canonical config table is allowed to run ahead of Base.** A row is
  authored when a ticker is chosen and Base is pinned when it is deployed, so
  the config table leads in that window; only the rows Base carries are read, so
  the excess is inert. The genuine error is a config table SHORTER than Base — a
  deployed Base row with no name/symbol to deploy under — which reverts
  `TokenTableTooShort(configsLength, baseLength)`. Row-for-row key drift between
  the two tables still reverts `TokenTableMisaligned`.
- **Three checks the gap-fill scripts had dropped are back, matching
  `20260706-deploy-tokens-ethereum`.** Each deployed vault is now read back
  before the loop moves on — `AuthoriserNotWired` if it is not routed to the
  chain's authoriser, `OwnershipHandoffFailed` if ownership did not land on the
  Safe — so a silent miss cannot finish the broadcast leaving a production vault
  inoperable or owned by the CI deploy key. A deploy call that emitted no
  `Deployment` event reverts `DeploymentEventMissing(underlying)` rather than
  carrying a zero address into the receipt readback.
- The two per-chain scripts' broadcast run ids are pinned into the token tables
  their runs produced, so deleting the scripts does not delete the record of
  what deployed each chain's set. `manual-broadcast.yaml`'s append-only rule now
  states the exception the deletion was made under: an entry may be dropped only
  when a named successor listed there covers its pre-flight at least as
  strongly, and the run id has been carried into the pin.
- **One dispatch ships a suite to every supported network.** Both
  `DeployProdV4_0_1_1` and `DeployProdV4_0_1_30` built a one-element `string[]`
  for `LibRainDeploy.deployAndBroadcast`, which takes a list and loops it, so
  the six-suite 0.1.30 rollout cost one dispatch per (suite, network) pair.
  `DEPLOYMENT_NETWORK=all` now hands the script's whole supported set to that
  loop, which forks each network in turn and skips any that already has code at
  the expected address — so a repeat dispatch is a no-op where the suite landed
  and a retry where it did not. Naming a single network still ships to that one
  only, and 0.1.1 still refuses `base`, by name and under `all` alike, because
  Base is absent from its supported set. Both workflows now pass `legacy: true`
  unconditionally: `--legacy` is one flag over the whole `forge script` run, so
  an all-networks run cannot vary the transaction type per network, and type-0
  is valid on every network these scripts ship to.

### New contracts

- **ST0xOrchestrator**: Singleton mint/burn proxy for the whole ST0x
  receipt-vault set (Initializable, one instance behind a `BeaconProxy`; all
  per-token state keyed by the token's vault address). Holds the vault's
  `DEPOSIT` + `WITHDRAW` roles and owns every ERC-1155 receipt; callers never
  touch one. Roles are split: `MINT_ROLE` mints, `BURN_ROLE` burns, and
  `EMERGENCY_ROLE` handles recovery (`setBurnIndex`, `withdrawReceipt`,
  `withdrawShares`, `sweepERC1155`) — deliberately separate so the key that can
  reposition pointers or sweep assets can never also mint. Every mint carries
  the recipient's own `MintAuthV1` authorisation of `(token, to, amount, nonce)`
  — an EIP-712 signature (ECDSA or EIP-1271) or, absent one, an
  `IMintRecipient.authorizeMint` callback on `to` — with replay protection
  namespaced by recipient: `(to, nonce)` is single-use. Burn walks a per-token
  sequential receipt-id pointer and reverts `InsufficientReceipts` on a
  shortfall — it NEVER mints to cover an overrun; recovery is manual (transfer
  receipts in, which auto-lower the pointer via the ERC-1155 receiver hook, or
  `EMERGENCY_ROLE` `setBurnIndex`). A vault-logic version lock makes
  `initialize` and `mint`/`burn` refuse to run unless the production vault +
  receipt beacons still point at the implementations pinned in
  `LibProdDeployV4`, halting the orchestrator until it is upgraded in lockstep
  with any vault-logic upgrade.
- **ST0xOrchestratorBeaconSetDeployer**: Deploys the `ST0xOrchestrator`
  singleton as a `BeaconProxy` behind a shared `UpgradeableBeacon` owned by the
  owner multisig. Config-in-constructor base; the Zoltu-deployable concrete
  subclass with hardcoded `LibProdDeploy*` config lands with the deploy wiring.

## V3 (corporate actions)

V3 introduces the corporate-actions diamond facet and wires it into the receipt
vault via a hardcoded `fallback()` delegatecall. Adds ERC-165 to deployers,
deployer interface inheritance, corporate action role admins on the authorizer,
and updates the upstream `rain.vats` dependency.

### New contracts

- **StoxCorporateActionsFacet**: Diamond facet implementing
  `ICorporateActionsV1`. Delegatecalled by `StoxReceiptVault` — direct calls
  revert with `FacetMustBeDelegatecalled`. Deployed at the deterministic Zoltu
  address recorded in `LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET`.

### StoxReceiptVault

- **Breaking** (bytecode): Overrides `fallback()` to route calls with
  non-matching selectors into `StoxCorporateActionsFacet` via delegatecall,
  using the deterministic address from `LibProdDeployV3`. `receive()` is not
  overridden — plain ETH transfers still bypass the facet. Changes the
  implementation codehash vs V2.

## V2 (Zoltu deterministic deployment)

Deployed via Zoltu factory — deterministic addresses identical across all EVM
networks (Arbitrum, Base, Base Sepolia, Flare, Polygon).

All contracts have parameterless constructors enabling Zoltu deployment.
Constructor dependencies (beacon owner, implementation addresses) are hardcoded
from constants.

### Addresses (all networks)

| Contract                                             | Address                                      | Constant                                                                       |
| ---------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------ |
| StoxReceipt                                          | `0xbAB0E6b7B5dDA86FB8ba81c00aEA0Ceb8b73686b` | `LibProdDeployV2.STOX_RECEIPT`                                                 |
| StoxReceiptVault                                     | `0xc95dB340A7a100881626475d41BFf70857Aa920D` | `LibProdDeployV2.STOX_RECEIPT_VAULT`                                           |
| StoxWrappedTokenVault                                | `0xb438a1eA1550fd199d67D67a69B71F4324bB8660` | `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT`                                     |
| StoxWrappedTokenVaultBeacon                          | `0x846a468e6fDA529D282D60df7D1EE785EB954600` | `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON`                              |
| StoxWrappedTokenVaultBeaconSetDeployer               | `0xBFB3D7Baece65D1f1640986CdA313177F1160C70` | `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER`                 |
| StoxOffchainAssetReceiptVaultBeaconSetDeployer       | `0x0C5154C4861908Bd5a6FD6fFCB063e9869ceFa41` | `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER`        |
| StoxUnifiedDeployer                                  | `0xeaE1c37b7aD1643D20da2B1b97705Fa949eAFaE7` | `LibProdDeployV2.STOX_UNIFIED_DEPLOYER`                                        |
| StoxOffchainAssetReceiptVaultAuthorizerV1            | `0x667d2Ab75908c7d7983008aDbF558332F381a5f5` | `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1`              |
| StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 | `0x72b2a394E129ede556b4024aCe939a964bA0a876` | `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1` |
| Beacon owner                                         | `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` | `LibProdDeployV2.BEACON_INITIAL_OWNER`                                         |

### New contracts

- **StoxWrappedTokenVaultBeacon**: Inherits `UpgradeableBeacon` with hardcoded
  implementation and owner from constants. Replaces the beacon that was
  previously created inline in the deployer's constructor.
- **StoxOffchainAssetReceiptVaultBeaconSetDeployer**: Inherits upstream
  `OffchainAssetReceiptVaultBeaconSetDeployer` with hardcoded config from
  constants. Replaces the upstream deployer that required constructor args.
- **StoxOffchainAssetReceiptVaultAuthorizerV1**: Inherits
  `OffchainAssetReceiptVaultAuthorizerV1` for Zoltu deployment. RBAC authorizer
  for receipt vault operations.
- **StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1**: Inherits
  `OffchainAssetReceiptVaultPaymentMintAuthorizerV1` for Zoltu deployment.
  Payment-gated minting authorizer with KYC verification.

### StoxWrappedTokenVault

- **Breaking**: Added `ZeroAsset` error and zero-address validation in
  `initialize(bytes)`. Initializing with `address(0)` now reverts instead of
  creating a bricked vault.

### StoxWrappedTokenVaultBeaconSetDeployer

- **Breaking**: Removed constructor params
  (`StoxWrappedTokenVaultBeaconSetDeployerConfig` struct removed). Beacon
  address is now referenced via
  `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON`.
- Removed `iStoxWrappedTokenVaultBeacon` immutable (beacon is referenced by
  constant address).
- Removed `ZeroVaultImplementation` and `ZeroBeaconOwner` errors (validation
  moved to beacon contract).
- Moved `Deployment` event emit before `initialize` call
  (checks-effects-interactions).

### StoxReceipt

- No bytecode changes from V1.

### StoxReceiptVault

- No bytecode changes from V1.

### StoxUnifiedDeployer

- **Breaking**: Now references V2 deployer addresses (`LibProdDeployV2`) instead
  of V1. Vault pairs created through the unified deployer use V2
  implementations.

### Deployment infrastructure

- All contracts deploy via `LibRainDeploy.deployAndBroadcast()` with address and
  codehash verification.
- `Deploy.sol` has one suite per contract, deployed sequentially in dependency
  order.
- Pointer files in `src/generated/` contain `BYTECODE_HASH`, `DEPLOYED_ADDRESS`,
  `CREATION_CODE`, and `RUNTIME_CODE` for each contract.
- `--skip-simulation` required for multi-chain broadcast of
  constructor-dependent contracts.
- Production constants split across `LibProdDeployV1` (Base V1 deployment) and
  `LibProdDeployV2` (Zoltu deterministic). Each version is fully self-contained.

## V1 (initial Base deployment)

Deployed via `new` in Forge broadcast scripts. Non-deterministic addresses. Base
only.

### Addresses (Base)

| Contract                                   | Address                                      | Constant                                                           |
| ------------------------------------------ | -------------------------------------------- | ------------------------------------------------------------------ |
| OffchainAssetReceiptVaultBeaconSetDeployer | `0x2191981Ca2477B745870cC307cbEB4cB2967ACe3` | `LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` |
| StoxWrappedTokenVaultBeaconSetDeployer     | `0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB` | `LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER`     |
| StoxWrappedTokenVault (implementation)     | `0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1` | `LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION`          |
| StoxUnifiedDeployer                        | `0x821a71a313bdDDc94192CF0b5F6f5bC31Ac75853` | `LibProdDeployV1.STOX_UNIFIED_DEPLOYER`                            |
| StoxReceipt (implementation)               | `0xE7573879D73455Dc92cB4087Fa8177594387CbCD` | `LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION`                      |
| StoxReceiptVault (implementation)          | `0x8EFfCe5Ebb047F215dF1d8522c32c7C9DE239f39` | `LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION`                |
| Beacon owner                               | `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` | `LibProdDeployV1.BEACON_INITIAL_OWNER`                             |

### Known issues

- `StoxWrappedTokenVault.initialize(bytes)` accepts `address(0)` as asset
  without reverting, creating a bricked vault. Fixed in V2.
