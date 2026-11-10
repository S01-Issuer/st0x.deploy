# Changelog

## Signed listing (RAI-4373)

### StoxCorporateActionsFacet

- **`IStoxListingV1.nameListing`: anyone first-names an unnamed V6 token.** The
  caller passes the token's asset id, ticker and underlying name, a Merkle
  proof, a listing root and a signature over the root. The facet reverts unless
  the token has that asset id (`ListingTokenHasNoAssetId`,
  `ListingAssetIdMismatch`) and no underlying ticker or name
  (`ListingAlreadyNamed`), the leaf of `address(this)` and the three fields is
  in the root (`ListingProofInvalid`), and the bound listing signer signed the
  root (`ListingSignerMismatch`, OpenZeppelin's `ECDSAInvalidSignature*`). It
  then writes the names as `setUnderlying` does and emits `ListingNamed`. After
  that only the owner renames, with `setUnderlying`. Errors are in
  `src/error/ErrListing.sol`.
- **The signed message holds on every chain.** `LibListing.digest(root)` is
  EIP-712 over `Listing(bytes32 root)` in the domain with name `ST0x Listing`
  and version `1`, with no chain id and no verifying contract. A V6 token's
  address is the same on every chain, so one signature names the same token on
  every chain, including chains added later. The leaf binds the token address,
  so a look-alike vault with the same asset id is never named from a listing.
- **The signer is bound under the governance timelock.** `nameListing` reads
  `st0x.listing-signer.v1` from the `ConfigRegistry` under
  `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK` at every call, so every bind
  and rebind of the signer is a timelock operation with the 48h delay. An
  unbound, mistyped or malformed binding reverts (`NameNotRegistered`,
  `ValueTypeMismatch`, `ListingSignerBindingMalformed`).
- **The facet suite depends on the `ConfigRegistry` and the governance
  timelock**, which its code embeds, so both must be on a chain before it.
- **Size.** The facet is 15,868 bytes. The vault does not change size: its
  fallback routes `nameListing` to the facet.

### Off-chain listing

- **`LibListingTree`** builds a listing off-chain exactly as OpenZeppelin's
  `StandardMerkleTree.of(rows, ["address","string","string","string"])`, from
  the token table's V6 rows: ticker = `underlying`, name = `underlyingName`. It
  is never linked into a deployed contract.
- **Pins moved:** facet `0x567cA22C1c8f4F070000F307Dfcaae0A96376Ba8`, receipt
  vault `0xA19377fb7e99D306CEa06f258C633453651a9054`, receipt-vault beacon
  `0x53f9cE6C82Ce7B7DBefC7164c9401Bd339D4577B`, orchestrator
  `0x356B4C54B17fe4a6af574ACF8C14b0675Faa98ea`, orchestrator beacon
  `0x3FD0E23c19F511093a59d60B08116cb3DC27bacd`, and the token and orchestrator
  proxy runtime code that embeds the beacons. Token and wrapper addresses do not
  move.

### The V6 listing

- **`LibV6Listing.ROOT`** is the listing of the leading 59 production V6 rows
  (`ROW_COUNT`) and the two test tokens, frozen: the signed rows are kept as
  data (`LibV6Listing.signedRows`), so a later issuer rename in the table does
  not move them, and `V6ListingTokenMoved` refuses a row whose token moved.
  **`script/BuildListing.sol`** writes it to `listing.json` with the digest the
  listing signer signs and, per row, the leaf, the proof and the factory call
  that deploys the token. `Git is clean` regenerates it.

## Asset id and nameless V6 deploy (RAI-4373)

### StoxReceiptVault

- **`initialize` requires an empty name and symbol and an asset id.** The vault
  overrides rain-vats' `_initialize`: after it, it delegatecalls the pinned
  facet's `initializeAssetId` with its own `initialize(bytes)` calldata, and
  reverts unless the call succeeds and returns one word. The facet reverts with
  `NonEmptyInitialName` / `NonEmptyInitialSymbol` unless both are empty, decodes
  the asset id from the config metadata (`LibAssetId.encodeMetadata`, tagged
  `st0x.metadata.asset-id.1`, canonical encoding enforced), and stores it once
  in a new ERC-7201 namespace `rain.storage.asset-id.1`. So a V6 token's address
  depends only on its asset id, region, authority and beacon names. The token is
  named later from a signed listing (`nameListing`) or by its owner with
  `setUnderlying`.
- **The hook is init-only.** It needs the OZ `_initializing` flag, which only a
  fresh proxy's single `initialize` sets. Live tokens, initialized before the
  hook, report `assetId() == ""` and can never set one. A facet with no code
  makes `initialize` revert `CorporateActionsFacetNotDeployed`, so no token
  deploys without an id.
- **Size.** The vault runtime is 24,555 bytes (21 spare), up 105 bytes; all the
  logic lives in the facet, which is 12,897 bytes.

### StoxCorporateActionsFacet

- **`IStoxAssetIdV1`:** `assetId()` and the `AssetIdSet(sender, assetId)` event,
  plus the init-only `initializeAssetId(bytes)`. Errors are in
  `src/error/ErrAssetId.sol`. `assetId()` and `AssetIdSet` are not proof that a
  token is genuine: only the pinned address is.

### StoxWrappedTokenVault

- **`assetId()` passes the asset's `assetId()` through**, or returns `""` when
  the asset has none, so it never reverts. Runtime 6,729 bytes.

### Token config and deploy

- **`TokenConfig.assetId`**, fixed at listing time (the ISIN of the exact share
  line where one exists). `LibProdTokenConfig.v6TokenConfigs()` is the rows with
  a non-empty asset id; only those get a V6 token suite.
- **Every production row has an asset id, so every row has a V6 token suite.**
  The ids are ISINs: 54 from the st0x.registry Base token list
  (`extensions.isin` at `e9e47a6`), and IBHG, RKLB, BIRD, SNES and DIS sourced
  from issuer and sponsor SEC filings (see `LibProdTokenConfigIsinTest`).
  `manual-sol-artifacts` offers one `stox-token-*` and one
  `stox-token-*-wrapper` choice per row; every token key is pinned, and each
  wrapper key derives from its token key. A V6 suite deploys a second token at a
  new address; it does not touch the live token. The `stox-token-*` choices
  deploy the token unnamed. The rollout runs the suite's pre-flight as a dry
  run, then deploys and names the token in one Multicall3 transaction (see "The
  V6 listing" in `docs/TIMELOCK.md`); the `-wrapper` choice then deploys its
  wrapper.
- **Test tokens carry asset ids.** `tUSTEST` and `tEUTEST` have the synthetic
  ids `ST0XTESTUS` and `ST0XTESTEU` and an underlying name, so they deploy
  nameless and a listing can name them. Their wrappers are salted by
  `keccak256(assetId)`, like the tokens.
- **V6 token params are nameless.** `LibProdTokenParams.tokenData` carries an
  empty name and symbol and the asset id as metadata, and the salt is
  `keccak256(assetId)`. Suite keys stay `stox-token-` + lowercase symbol; a
  released row's symbol never changes, and the released keys are pinned.
- **`Deploy.preDeployCheck` refuses a token suite unless the bound vault beacon
  serves `LibProdDeployCurrent.STOX_RECEIPT_VAULT`**
  (`BeaconImplementationMismatch`, or `VaultBeaconNotDeployed` when the bound
  beacon has no code). A token's address commits to the beacon name, not the
  implementation, so a token deployed through a beacon serving a hook-less
  implementation would never get an asset id.
- **`Deploy.preDeployCheck` refuses a beacon or token suite unless the
  governance timelock that owns them is in its pinned state**
  (`LibTimelockInvariants.assertTimelockState` with the chain's Safe as
  proposer, so `TimelockNotDeployed`, `TimelockCodehashMismatch`,
  `TimelockMissingRole` and the other `LibTimelockController` errors). It runs
  after the binding checks. `stox-orchestrator-beacon` now goes through the
  beacon branch too, so it is refused unless the beacon initial owner binding is
  `STOX_GOVERNANCE_TIMELOCK` (`NameNotRegistered` when unbound,
  `BeaconInitialOwnerMismatch` when bound to another address); before, it had no
  check.
- **Pins moved:** facet `0xEcbC00c59019fe72628bE5e70E01BcF31460301D`, receipt
  vault `0x45C8FeF0bBa6230759F28DC7328DE50Da8f7008F`, wrapped token vault
  `0x8405cb839951dECd3D0bbb620e809A3eE300616b`, receipt-vault beacon
  `0x6Bd545bdbc624953FC599985d67684CabAB825F7`, wrapped-token-vault beacon
  `0x9804E0810Ae2776dC9a398838796438D94Db5e23`, orchestrator
  `0xE2375DCb679aC52B8D7EebCF154d4AaFc1c9A09f`, orchestrator beacon
  `0xF605c034E2D16D39f656A7F12AF6cb04D7Cef329`, and the token, wrapper and
  orchestrator proxy runtime code that embeds the beacons.

## Registry-config tokens (rain.vats 0.2.9)

### StoxReceiptVault

- **Built on rain.vats 0.2.9's abstract `OffchainAssetReceiptVault`.** It
  initializes from the ConfigRegistry and makes its receipt as a V6 registry
  beacon proxy, so a token has the same address on every chain. The beacon-set
  deployers are removed; tokens are V6 `registryBeaconProxy`s.
- **`optimizer_runs` lowered 1666 → 200 to fit EIP-170.** At 200 runs the
  runtime is 24,418 bytes (158 spare). As with every optimizer change, this
  moves every candidate Zoltu address; the candidate pins are regenerated.

### StoxReceipt

- **`uri` names "the underlying off-chain asset".** The vault's `asset()` is
  `address(0)`, so the inherited symbol read reverted, and with it `uri`, which
  the vault checks at `initialize`.

### Underlying ticker and name

- **`IStoxUnderlyingV1`: each receipt vault stores its underlying ticker and
  name.** `StoxCorporateActionsFacet` implements `underlyingSymbol()`,
  `underlyingName()` and `setUnderlying(symbol, name)`, with the values in a new
  ERC-7201 namespace `rain.storage.underlying.1` (`LibUnderlying`). The setter
  is `onlyOwner`-equivalent (it checks the vault's `owner()`, so on live chains
  it goes through the governance timelock), rejects empty values with
  `EmptyUnderlyingSymbol` / `EmptyUnderlyingName`, emits `UnderlyingSet` with
  the old and new values, and can be called again when a listing is renamed.
- **Token metadata is built from those values.** Once set, `StoxReceiptVault`
  reports `symbol() = "t" + ticker` and `name() = name + " (ST0x)"`, and
  `StoxWrappedTokenVault` reports `symbol() = ticker + "s"` and the vault's
  `name()` — e.g. `tNVDA` / `NVDAs`, both named `NVIDIA Corporation (ST0x)`. The
  suffix is the single constant `ST0X_NAME_SUFFIX`. While unset, the vault
  reports the name and symbol it was initialized with and the wrapper
  `"Wrapped " + name` / `"w" + symbol`, so nothing changes on chain until the
  values are set.
- **The wrapper does not revert because of its asset's underlying getters.** It
  reads the underlying values with a `staticcall` and falls back to the asset's
  ERC-20 metadata if the call fails, returns data that is not a well-formed
  `string`, or returns an empty value, so assets that are not ST0x receipt
  vaults still wrap. The asset's own `name()` / `symbol()` are called directly,
  as before, and a revert there still reverts the wrapper's view.
- **`setUnderlying` writes the vault's ERC-20 name and symbol once.** Besides
  the underlying values, it writes `"t" + ticker` and `name + " (ST0x)"` into
  OZ's own `ERC20Storage` (`LibERC20Storage.getStorage`), so the vault keeps
  OZ's plain storage-reading `symbol()` / `name()` and reading them never
  touches the facet. The formatting lives only in the facet. The vault has no
  room under EIP-170 for read-time formatting (main leaves 158 bytes); this
  design adds 26 bytes, the facet-presence check below, for 24,444 bytes (132
  spare). The initialized name and symbol are overwritten; they stay on record
  in the vault's initialization event. A later name-format change means calling
  `setUnderlying` again on each token.
- **The vault's `fallback()` reverts with `CorporateActionsFacetNotDeployed`
  when the pinned facet address has no code**, so a facet call (a corporate
  action, `setUnderlying`) made before the facet is deployed fails instead of
  succeeding as a no-op.
- **The wrapper's name is its asset's own name once the asset reports an
  underlying name**, so the name format lives only in the facet and a format
  change needs no wrapper upgrade.
- **Rollout order:** deploy the facet, upgrade the wrapper beacon, upgrade the
  receipt-vault beacon, then call `setUnderlying` (`docs/TIMELOCK.md`).
- As with every vault/facet change, the vault, facet, wrapper and the contracts
  that pin them move to new Zoltu addresses; the `candidate/` pins are
  regenerated.

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

- **`optimizer_runs` lowered 2000 → 1666 to fit the rain-math-float bump under
  EIP-170.** Float 0.2.22 → 0.3.3 (0.2.61 and 0.3.3 compile to identical
  bytecode) grows `StoxReceiptVault` to 24,757 at 2000 runs (over by 181).
  Measured: `runs=2000` → 24,757; `runs=1800` → 24,607 (over by 31); `runs=1667`
  → 24,580 (over by 4); `runs=1666` → 24,030 (**546 spare**); `runs=1000` →
  23,728.

  As with 5000 → 2000, this moves the bytecode and deterministic Zoltu address
  of every contract; all 12 `src/generated/candidate/` pins are regenerated.

  - No user-facing address moves.
  - ⚠️ **This is a coordinated multi-contract release.** `StoxReceiptVault`,
    `StoxCorporateActionsFacet` and `StoxReceipt` deploy in lockstep, for the
    reasons given under 5000 → 2000 above.
  - The frozen `0_1_1` and `0_1_30` snapshots are untouched and
    `testFrozenRedeploy*` still redeploys them.
  - rain-deploy's `TimelockController` creation code was built at 2000 runs, so
    it no longer reproduces under this profile. Tests build timelocks from that
    pinned creation code, and the governance-timelock verify step in
    `manual-broadcast.yaml` compiles with rain-deploy's settings via
    `script/timelock-verify.sh`, whose `check` (CI: `timelock-verify-check`)
    proves that compile reproduces the pinned creation and runtime code.

### Deploy scripts

- **The underlying-naming rollout.** `LibUnderlyingNamingRollout` reconstructs
  two timelock operations per chain:
  - a beacon batch that upgrades the in-use wrapped-token-vault and
    receipt-vault beacons and then probes the facet, so it reverts if the facet
    is missing;
  - a rename batch of `setUnderlying` on every production vault, with the beacon
    batch as its predecessor.

  `20261021-schedule-underlying-naming-beacons` and `-rename` author the Safe
  bundles that schedule them, and `20261021-execute-underlying-naming` executes
  the next ready one from the CI deploy key.
  `20261021-deploy-underlying-naming-implementations` and both schedule scripts
  refuse until the implementations are a frozen, audited release
  (`LibUnderlyingNamingRollout.RELEASE_FROZEN`). The rename covers a fixed
  number of leading table rows per chain, so a later token gets its own
  operation. `TokenConfig` gains `underlyingName`, the issuer's name without the
  ST0x suffix.
- **The rename script refuses until downstream is ready.** It requires
  `LibUnderlyingNamingRollout.DOWNSTREAM_ACCEPTS_NEW_SYMBOLS` (false until the
  services and token lists accept `<TICKER>s`), and every row's ticker and
  underlying name to be well formed, so a quote or backslash never reaches the
  receipt's `uri()` JSON and a row cannot carry the ST0x suffix twice.
- **Downstream is ready: `DOWNSTREAM_ACCEPTS_NEW_SYMBOLS` is set.**
  st0x.liquidity accepts both `wt<TICKER>` and `<TICKER>s` from release v1.29.0,
  st0x.pricing and st0x-oracle-server never read an on-chain `symbol()`, and the
  st0x.registry lists carry `nextSymbol` / `nextName`. The rename script still
  refuses until `RELEASE_FROZEN` is set. The head-fork name pins
  (`LibProdTokenConfigTest` and `StoxCrossChainParityTest`) accept each token in
  its initialized or renamed state, so they stay green as each chain renames.
  The `wt*` pins in `LibTokenInvariants.addresses.t.sol` fork at a pinned
  pre-rename block and also accept `<TICKER>s`, for a later block bump.
- **Orchestrator ordering, corrected.** The orchestrator's vault-logic lock
  reads the 0.1.30 beacon-set deployer's beacons, not the in-use token beacons,
  so the rule that the admin move precedes beacon upgrades names that set. A
  Base fork test mints and burns through the live orchestrator after the in-use
  beacons move.

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
- **One dispatch ships a suite to every network.** Both `DeployProdV4_0_1_1` and
  `DeployProdV4_0_1_30` built a one-element `string[]` for
  `LibRainDeploy.deployAndBroadcast`, which takes a list and loops it, so the
  six-suite 0.1.30 rollout cost one dispatch per (suite, network) pair. Both now
  hand it `LibStoxDeployNetworks.deploymentNetworks` — Base, Ethereum, HyperEVM
  — which the loop forks in turn, skipping any that already has code at the
  expected address, so a repeat dispatch is a no-op where the suite landed and a
  retry where it did not. Picking a network is gone with it: the
  `DEPLOYMENT_NETWORK` env var, the `network` choice on both workflows and the
  per-script supported-network lists are all removed, leaving one declaration of
  the set in `LibStoxDeployNetworks`. 0.1.1 no longer excludes Base — the whole
  audited 0.1.1 set already has code at its pinned addresses there, as
  `StoxProdV4Test` asserts per chain, so the exclusion had nothing left to
  express and the run is a no-op on all three. Both workflows now pass
  `legacy: true` unconditionally: `--legacy` is one flag over the whole
  `forge script` run, so it cannot vary per network within a run, and type-0 is
  valid on every network these scripts ship to.

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

### Subgraph

- **`subgraph/` indexes role holders, role admins and ownership.**
  `AccessControl` exposes no member list, so a role's current holders exist
  nowhere on chain as readable state — only the `RoleGranted` / `RoleRevoked`
  log stream has them, and public RPCs cap `eth_getLogs` at 1000 blocks, which
  makes trawling that stream impractical on the chains ST0x deploys to. The
  subgraph answers, per contract per chain: current holders of a role and the
  count, the full grant/revoke history with both the event `sender` and the
  transaction submitter, the current role admin and its history, and the current
  owner and its history — plus the current implementation and upgrade history of
  each beacon. One deployment per network, built and deployed by the rainix
  subgraph tooling to Ormi (`.github/workflows/subgraph-test.yaml`,
  `.github/workflows/deploy-subgraph.yaml`).

  The indexed set is the five networks in
  `LibStoxDeployNetworks.deploymentNetworks()`. Six static data sources — the
  authoriser clone, the governance timelock, the wrapped-token-vault beacon, the
  orchestrator beacon and the two beacon-set deployers — plus three templates.
  Receipt vaults and orchestrators are discovered from their deployers'
  `Deployment` events rather than enumerated, because listing 54 tokens a chain
  by address would take roughly 61 data sources per network.

  Two caveats are deliberate. `startBlock` is 0 on every network: no deploy
  block is recorded anywhere in this repo, and 0 is the only lower bound that
  cannot silently drop grant or revoke history — it costs initial sync time, not
  correctness. And the receipt and receipt-vault beacons are created in the
  beacon-set deployer's constructor, in a block that precedes any `Deployment`,
  so their construction-time logs are not reachable from the template that
  discovers them; their owner and implementation are read by call at discovery
  instead, which `Contract.ownerFromLog` / `Contract.implementationFromLog`
  report per row.

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
