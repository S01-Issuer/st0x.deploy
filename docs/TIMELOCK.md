# ST0x Governance Timelock

## What it is

An **unmodified, pre-audited OpenZeppelin `TimelockController`** (compiled from
the version-locked `@openzeppelin-contracts` 5.6.1 soldeer dependency) that sits
between the token-owner Safe and the privileged surfaces of the ST0x deployment.
After the migration executes, the timelock is:

- the `owner()` of **every production receipt vault** — so `transferOwnership`,
  `setAuthorizer`, `setUnderlying`, and every `onlyOwner` surface (including
  owner freezes) is delay-gated;
- the `owner()` of the chain's **four in-use upgrade beacons** (receipt, receipt
  vault, wrapped token vault, orchestrator) — so `upgradeTo` is delay-gated; and
- the **sole holder of the authoriser's seven `_ADMIN` roles** (`DEPOSIT_ADMIN`,
  `WITHDRAW_ADMIN`, `CERTIFY_ADMIN`, `CONFISCATE_SHARES_ADMIN`,
  `CONFISCATE_RECEIPT_ADMIN`, `SCHEDULE_CORPORATE_ACTION_ADMIN`,
  `CANCEL_CORPORATE_ACTION_ADMIN`) — so adding or removing grants on the
  authoriser is delay-gated.

- the **sole holder of the orchestrator's `DEFAULT_ADMIN_ROLE`** (once
  `20261006-orchestrator-admin-to-timelock` executes) — so granting or revoking
  `MINT`, `BURN` and `EMERGENCY` on the orchestrator is delay-gated.

**Why the beacons are in scope.** Every production token proxies through those
beacons, and a beacon owner can `upgradeTo` a new implementation for all of them
in a single transaction — a hostile implementation could re-take vault ownership
and rewrite the authoriser wiring outright. Timelocking `setAuthorizer` and
vault ownership while leaving the beacons on the Safe would make the delay
bypassable by design, so both surfaces moved in the same atomic bundle, and
`GovernanceTimelockMigration.t.sol` pins both on the timelock.

The Safe **keeps its three direct action roles** (`DEPOSIT`, `WITHDRAW`,
`CERTIFY`) and the service signer keeps its operational grants: day-to-day
operations are NOT timelocked. Only admin power is.

No deployed ST0x contract changes for any of this — the timelock is purely a
deployment-config choice (the owner/admin principal moves from the Safe to the
timelock). That keeps the audited contract set untouched.

## The mint-caps orchestrator

The mint-caps `ST0xOrchestrator` is a fresh deployment that runs next to the
live orchestrator (`0x3A7387a484d87Aa8bBA45E98AAB401Ce4FBF03E2`); minters move
over once it is ready. The live orchestrator and its beacon are not upgraded in
place. The new one has its own beacon, because different code needs a different
beacon.

Its admin is read from the `ConfigRegistry` under
`LibRegistryAuthority.ROOT_AUTHORITY` rather than compiled in or passed by the
deployer, so the creation code is chain-invariant and no migration bundle moves
admin power:

- **Beacon.** `ST0xOrchestratorBeacon` is a Zoltu-deployed `UpgradeableBeacon`
  serving `LibProdDeployCurrent.ST0X_ORCHESTRATOR`, owned by the registry-bound
  `LibStoxConfig.beaconInitialOwner()`. The deploy key never owns it, and with
  the governance timelock bound, `upgradeTo` is delay-gated. Its constructor
  reverts while the binding is unset or zero.
- **Instance.** A rain-factory registry beacon proxy over the beacon bound under
  `LibStoxConfig.ORCHESTRATOR_BEACON_NAME`; its address commits to the registry,
  authority and beacon name, so it is the same on every network. `initialize`
  grants the registry-bound initial admin `DEFAULT_ADMIN_ROLE`,
  `MINT_ADMIN_ROLE`, `BURN_ADMIN_ROLE` and `EMERGENCY_ADMIN_ROLE`, and nothing
  else. It takes no admin argument, so whoever creates the proxy cannot seat an
  admin of its own, and it reverts while the binding is unset, not an `address`,
  or zero. Production binds the initial admin to the governance timelock.
- **Suites.** `StoxDeploySuites` declares the implementation and the beacon as
  Zoltu suites and the instance as the `stox-orchestrator-proxy` registry beacon
  proxy suite, pinned to `LibST0xOrchestratorProxy.RUNTIME_CODE`.
- **Operating roles** (`MINT_ROLE`, `BURN_ROLE`, `EMERGENCY_ROLE`) are granted
  by their admin role, so each grant is a scheduled timelock operation.
- **Configuration.** The mint weighting and the per-minter and per-recipient
  mint limits are `MINT_ADMIN_ROLE` surfaces, so setting or changing them waits
  out the delay too.

Each admin role administers its operating role and itself, so
`DEFAULT_ADMIN_ROLE` cannot grant an admin role: the grants in `initialize` are
the only way a first holder is seated, and losing every holder of one takes a
beacon upgrade to recover.

## Role model

| Role on the timelock | Holder                                                 | Meaning                                                         |
| -------------------- | ------------------------------------------------------ | --------------------------------------------------------------- |
| `PROPOSER_ROLE`      | token-owner Safe                                       | schedules operations                                            |
| `CANCELLER_ROLE`     | token-owner Safe (+ dedicated canceller, once decided) | vetoes a scheduled operation inside the window                  |
| `EXECUTOR_ROLE`      | `address(0)` — i.e. anyone                             | executes once the delay elapses                                 |
| `DEFAULT_ADMIN_ROLE` | the timelock itself                                    | role changes are themselves timelocked (OZ self-administration) |

- **Execution is permissionless.** `EXECUTOR_ROLE` is granted to `address(0)`,
  which OZ's `onlyRoleOrOpenRole` reads as "open to everyone", so once the delay
  has run ANYONE may execute a scheduled operation. The operator cannot censor a
  matured operation, and the Safe executes as a member of the public rather than
  by privilege. `cancel()` has no open-role path in OZ, so vetoing stays
  privileged — the asymmetry is the design.
- **Operations never expire.** OZ keeps a matured operation executable
  indefinitely. With open execution that means a scheduled-then-abandoned
  operation can be executed by anyone, at any later time. An operation you
  decide against must be CANCELLED, not merely left unexecuted.
- **Min delay: 48 hours** (`LibTimelockInvariants.TIMELOCK_MIN_DELAY`). Changing
  it is a timelocked `updateDelay` operation and must update the pin in the same
  operational window.
- **The deployer holds nothing, ever.** The constructor passes
  `admin = address(0)`, so it grants the deployer no role — there is no
  configuration window and nothing to revoke.
- **No open roles.** OZ treats a zero-address grantee as "role open to
  everyone"; `assertTimelockState` rejects that on every lifecycle role.
- **Dedicated canceller.** The OZ constructor grants cancellership to proposers,
  so the Safe can always cancel. A separate canceller principal is optional and
  lives in `LibTimelockInvariants.TIMELOCK_CANCELLER`: while that pin is
  `address(0)` no extra canceller is expected, and once it is non-zero
  `assertTimelockState` asserts the grant. Provisioning one is itself a
  timelocked operation — schedule `grantRole(CANCELLER_ROLE, canceller)` on the
  timelock and hydrate the constant in the same operational window. It cannot be
  set in the constructor, which takes no canceller argument.

## Addresses

The timelock is deployed via the **Zoltu deterministic factory**: its address is
a pure function of its creation code. `StoxGovernanceTimelock` (the
`stox-governance-timelock` suite) reads its initial proposer from the
`ConfigRegistry` under `TIMELOCK_INITIAL_PROPOSER_NAME`
(`st0x.timelock-initial-proposer.v1`), so its creation code, and its address, is
the same on every chain.

The five live timelocks take the chain's Safe as a constructor arg, so each sits
at a distinct address —
`LibTimelockInvariants.expectedTimelockAddress(chain's Safe)`. Their pins stay
until governance moves to the suite timelock.

Constants (in `src/lib/LibTimelockInvariants.sol`) that future scripts and
invariants target:

| Constant                             | Holds                                     |
| ------------------------------------ | ----------------------------------------- |
| `STOX_GOVERNANCE_TIMELOCK`           | the Base timelock                         |
| `STOX_GOVERNANCE_TIMELOCK_ETHEREUM`  | the Ethereum timelock                     |
| `STOX_GOVERNANCE_TIMELOCK_HYPEREVM`  | the HyperEVM timelock                     |
| `STOX_GOVERNANCE_TIMELOCK_ROBINHOOD` | the Robinhood Chain timelock              |
| `STOX_GOVERNANCE_TIMELOCK_BSC`       | the BNB Smart Chain timelock              |
| `TIMELOCK_CANCELLER`                 | the dedicated canceller, once provisioned |

Every pin is written with its chain arm, derived from the frozen creation
bytecode and that chain's Safe pin before any deploy —
`testPinsMatchDerivedAddresses` asserts each equality unconditionally, so a
wrong or zeroed pin cannot survive CI. A zero pin is never a legitimate phase:
every consumer (the migration authoring, `assertTimelockState`) refuses it as a
reverted or never-hydrated arm rather than proceeding against a wrong address.
All five timelocks are live at their pins.

## Rollout (per chain: Base, Ethereum, HyperEVM, Robinhood Chain, BNB Smart Chain)

The five chains run the per-Safe timelocks at their `LibTimelockInvariants` pins
(see Addresses), so steps 1-2 do not apply to them. Steps 1-2 are the path for a
chain whose timelock is the `stox-governance-timelock` suite.

1. **Bind the Safe** — bind the chain's governance Safe under
   `TIMELOCK_INITIAL_PROPOSER_NAME` in the `ConfigRegistry`. The constructor's
   typed resolve reverts on an unset name, so the bind always precedes the
   deploy.
2. **Deploy** — Actions → `manual-sol-artifacts` → `stox-governance-timelock`.
   The Zoltu suite lands at one address on every network; that chain's
   `timelockForChainId` arm then returns
   `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK`, and `assertTimelockState`
   requires `STOX_GOVERNANCE_TIMELOCK_CODEHASH` there.
3. **Author the migration bundle** — Actions → `run-script` →
   `20260729-migrate-governance-to-timelock`, network `base` / `ethereum` /
   `hyperevm` / `robinhood` / `bsc`. Emits the Safe Tx Builder JSON
   (`out/20260729-governance-timelock-migration-<chainid>.json`) after a full
   pre-flight, simulation, post-state assertion, and an end-to-end schedule →
   48h → execute proof on the fork. The logged MultiSend `SafeTxHash` is the
   signer cross-check.
4. **Sign + execute** — import the CI-authored artifact into the Safe UI (never
   a locally generated JSON). Before signing, each signer runs the local
   integrity check against a live fork —
   `forge script script/20260729-migrate-governance-to-timelock.s.sol --sig 'verify(string)' <downloaded.json> --rpc-url <network>`
   — which re-derives the bundle from current chain state, asserts the artifact
   matches byte-exactly, and prints the MultiSend `SafeTxHash` at the live nonce
   to cross-check in the Safe UI. Then execute. The bundle is atomic: 7 `_ADMIN`
   grants to the timelock → N vault `transferOwnership` → one beacon
   `transferOwnership` per in-use beacon (four) → 7 Safe renounces.
5. **Post-execution flip** — every production invariant asserts the timelock
   exactly: beacon owner
   (`LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock`,
   `LibOrchestratorInvariants.assertBeaconSet`) and `_ADMIN` holder
   (`LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe, timelock)`).
   The migration has executed on all five chains, so this is the current state.
   Vault owner is asserted only by the migration scripts' own pre-flights and
   post-states: the post-states and the rename pre-flight call
   `LibTokenInvariants.assertUniformOwnership`, and the handover and governance
   pre-flights read `owner()` in their own loops, since they accept the Safe or
   the timelock.

`GovernanceTimelockMigration.t.sol` pins the governed state on every chain. The
migration script's own tests rewind each fork to the pre-migration state with
the timelock's powers, so the script stays re-dispatchable and proven.

### Safe-owned Base vaults: tWMT, tMC, tDIS, tIFX, tSOI and tTPRO

These six are the token-table Base vaults still owned by the Safe; every other
token-table Base vault is timelock-owned. tQSEP
(`0x4A9a9FC94a507559481270d0BFf3315Ab92Fcefa`) is not in the token table, so
this migration does not move it, and the Safe still owns it. The rename batch
calls `setUnderlying` on tWMT, tMC and tDIS, so those must be on the timelock
first, and nothing else can move tIFX, tSOI and tTPRO once the V5 backfill
records the 2026-07-29 governance migration.

`20261103-hand-safe-owned-base-vaults-to-timelock` sits on every chain's root
line after the orchestrator admin move, which follows the beacon initial owner
bind and the V5 backfill. On Base its bundle is one
`transferOwnership(timelock)` per vault of the six the Safe still owns, plus the
record; elsewhere it is the record alone. The pre-flight requires every other
token-table Base vault, and the rename's rows elsewhere, to be timelock-owned. A
vault of the six that the timelock already owns is skipped.

Decide Base Safe nonce 706 first. It is the Safe's older queued MultiSend that
moves the same six (from `20260729-migrate-governance-to-timelock`), and it is
the Safe's next nonce, so the V5 backfill and every later Safe bundle on Base
wait on it. Before signing the backfill, either execute 706, and this
migration's Base bundle is the record alone, or reject it, and the bundle moves
the six. To execute, per chain:

1. On Base, before signing, cancel any pending timelock operation against the
   six vaults: once the timelock owns them, anyone can execute it. Find them on
   the rain-org-health dashboard's Role changes tab
   (<https://rainlanguage.github.io/rain-org-health/deployments.html>), or with
   the same read against the RBAC subgraph (`st0x-rbac-base`, version `prod`):
   `{ timelockOperations(where: {timelock: "<timelock>", status: PENDING, targets_contains: ["<vault>"]}) { operationId readyAt calls { target data } } }`
   per vault. `cancel` reverts on anything not pending.
2. Actions → `run-script` → `20261103-hand-safe-owned-base-vaults-to-timelock`,
   the network, `run()`.
3. Every signer, the proposer included, unzips the artifact into `out/` and runs
   `forge script script/20261103-hand-safe-owned-base-vaults-to-timelock.s.sol --sig 'verify(string)' out/<artifact>.json --rpc-url <network>`
   before signing.
4. One signer imports the CI artifact into the Safe Tx Builder and proposes it
   without executing. When the bundle has more than one transaction, the
   `SafeTxHash` that `verify` printed must equal the one in the Safe UI. A
   one-transaction bundle (the record alone, off Base or on Base after 706) is
   proposed by the Safe UI as a direct call rather than the `MultiSend` that
   `verify` hashes, so compare the call's target and data with the artifact
   instead. Then sign to threshold and execute.

Rollback on Base: the Safe schedules `transferOwnership(safe)` on the moved
vaults through the timelock; anyone executes it after 48h. Trap: the record and
the root-line head stay, so this migration cannot run again, and the rename
pre-flight refuses the vaults back on the Safe. Rolling forward again needs a
new migration.

## Rehearsing the timelock

The rehearsed operation (rain-deploy's `LibTimelockRehearsal`, salt
`keccak256("st0x.timelock.rehearsal.20260813")`) is
`timelock.updateDelay(TIMELOCK_MIN_DELAY)` — re-setting the delay to the value
it already holds. It is a genuine no-op, it targets the timelock rather than any
production contract, and OZ rejects `updateDelay` from any caller other than the
timelock itself, so it can only happen via the full schedule → delay → execute
path.

The rehearsal ran on Base only. Its three scripts are history-only on every
chain:

1. `20260813-timelock-rehearsal-schedule` — the schedule.
2. `20260813-timelock-rehearsal-cancel` — the cancel.
3. `20260813-execute-timelock-operations` — the permissionless execute.

Each script's `run()` refuses on every chain. The backfill bundle
(`20261030-backfill-migration-registry-v5`) writes their root-line records: on
Base as history at each script's `executedAt`, elsewhere record-only.

The salt is fixed, so the operation id is fixed per chain and OZ keeps the
executed operation registered on Base; rehearsing again needs a new salt, i.e. a
new dated rehearsal.

## Operating under the timelock (future governance actions)

Every admin action becomes two Safe transactions separated by ≥48h:

1. **Schedule**: Safe → `timelock.schedule(target, 0, data, 0, salt, 172800)`
   where `data` is the admin call (e.g.
   `authoriser.grantRole(DEPOSIT, newSigner)`,
   `vault.setAuthorizer(newAuthoriser)`, `vault.transferOwnership(newOwner)`).
   Batch multiple calls with `scheduleBatch`.
2. **Wait** out the delay. Anyone can watch pending operations on the
   rain-org-health dashboard's Role changes tab,
   <https://rainlanguage.github.io/rain-org-health/deployments.html>, which
   reads each network's timelock operations live from this repo's RBAC subgraph
   (`st0x-rbac-<network>`, version `prod`); the Safe (or the dedicated
   canceller, once provisioned) can `cancel(id)` during the window.
3. **Execute**: Safe → `timelock.execute(target, 0, data, 0, salt)` (or
   `executeBatch`) with the identical arguments.

Operational scripts that author such bundles follow the existing dated
`run-script` pattern — they should build the schedule/execute calldata against
`LibTimelockInvariants` constants, and each script's simulation should include
the same warp-and-execute loop proof the migration script uses.

**Key invariant for script authors**: the Safe can no longer call `onlyOwner` /
`_ADMIN`-gated functions directly. Any script that authors a Safe bundle
targeting those surfaces must target the timelock instead, and
`LibTimelockInvariants.timelockForChainId(block.chainid)` is the only sanctioned
way to resolve it.

**Upgrading the receipt vault.** The vault delegatecalls the corporate-actions
facet at `LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET`, a constant built
into its bytecode. A vault implementation whose facet is not deployed keeps its
ERC-20 metadata, but every facet call, `setUnderlying` included, reverts with
`CorporateActionsFacetNotDeployed`. The underlying-naming rollout runs in this
order on every chain; `LibUnderlyingNamingRollout` reconstructs both timelock
operations, and `20261021-underlying-naming-rollout.t.sol` runs the whole
sequence on a fork of each chain.

0. The chain's root line must already hold, in order, the V5 backfill
   (`20261030-backfill-migration-registry-v5`), the beacon initial owner bind
   (`20261022-bind-beacon-initial-owner`), the orchestrator admin move
   (`20261006-orchestrator-admin-to-timelock`), and the Safe-owned Base vault
   handover (`20261103-hand-safe-owned-base-vaults-to-timelock`, the record
   alone off Base). The beacon schedule refuses at any other head.
1. Deploy the three implementations at their Zoltu addresses (permissionless):
   the facet, the receipt-vault implementation and the wrapped-token-vault
   implementation named in `LibUnderlyingNamingRollout`, by dispatching the
   `stox-corporate-actions-facet`, `stox-receipt-vault` and
   `stox-wrapped-token-vault` suites through `manual-sol-artifacts`. The beacon
   script's pre-flight checks each codehash against its pin before scheduling.
   Each chain's beacon and rename operation ids are pinned
   (`LibUnderlyingNamingRollout.pinnedOperationIds`). Once a chain's batch is
   scheduled, its pins and the rows and constants they hash must not change: a
   changed batch needs a new salt and a new script, not a re-pin. Each schedule
   script's first Safe bundle ends in its root-line record (a reschedule after a
   cancel is the schedule alone); no record rides in a timelock batch.
2. Schedule the beacon batch (`20261021-schedule-underlying-naming-beacons`):
   one `scheduleBatch` that upgrades the chain's in-use wrapped-token-vault
   beacon, then its in-use receipt-vault beacon
   (`LibBeaconInvariants.prodBeaconsForChainId`), then calls
   `completedActionCount()` on one production vault. That last call reverts if
   the facet has no code, so the batch cannot land without it. `upgradeTo`
   likewise rejects an implementation with no code. A reverted `executeBatch`
   rolls back and leaves the operation Ready with its delay spent: deploy what
   is missing and execute the same batch again. A new delay is needed only if
   the operation is cancelled or its arguments change. To reschedule a batch the
   Safe cancelled, dispatch its schedule script again: its record is already on
   the root line, so it authors the schedule alone and the line does not move.
   If both batches were cancelled, reschedule the beacon batch first, then the
   rename. Both pre-flights refuse unless the derived operation id equals the
   pinned one (`LibUnderlyingNamingRollout.pinnedOperationIds`). A reschedule is
   valid only for an unchanged batch the Safe cancelled to pause this rollout,
   never for one cancelled under the stale-batch rule below; before signing it,
   check that no other beacon upgrade is pending. A rescheduling bundle is one
   call, which the Safe UI proposes as a direct call rather than the `MultiSend`
   that `verify` hashes: compare the call's target and data with the artifact
   instead of the `SafeTxHash`. To halt the rollout while the beacon batch is
   pending, cancel both: a rename left pending becomes executable again as soon
   as a rescheduled beacon batch executes. Cancel the rename first, in its own
   Safe transaction, then the beacon batch in another: in one bundle, a beacon
   batch that executes while signatures are collected makes its `cancel` revert
   and rolls back the rename's cancel too. The rollout is halted only once the
   rename operation reads unset. Once the beacon batch is Done, `cancel` reverts
   on it, so cancel the rename alone. If only the beacon batch was cancelled,
   the pending rename waits for the rescheduled beacon batch, its predecessor,
   and the execute script waits for it too. The wrapper keeps its current name
   and symbol while the vault has no underlying set. The orchestrator's
   vault-logic lock reads the 0.1.30 beacon-set deployer's beacons, not the
   in-use ones, so it does not cover this upgrade: minting and burning keep
   running across it (the Base fork test mints and burns through the live
   orchestrator after the batch); the orchestrator admin move still comes first
   on the root line (step 0). It also means the lock does not watch the logic
   production tokens run; pointing it at the in-use beacons is a separate
   orchestrator change.

   The pre-flight also requires each beacon to still serve the implementation
   the batch moves it from (`RECEIPT_VAULT_FROM_IMPLEMENTATION`,
   `WRAPPED_TOKEN_VAULT_FROM_IMPLEMENTATION`), owned by the chain's timelock,
   with the pinned beacon codehash. **Stale batches:** before the Safe schedules
   any other upgrade of a chain's receipt-vault or wrapper beacon, it must
   `cancel` that chain's pending beacon batch and its rename batch. Otherwise
   the stale batch stays Ready after its delay and anyone can execute it later,
   which rolls the beacons back to this rollout's implementations. After such a
   cancel the rollout resumes only through a reviewed change onto the new
   from-implementations, not a reschedule.
3. Schedule the rename batch (`20261021-schedule-underlying-naming-rename`): one
   `scheduleBatch` of `setUnderlying(ticker, underlyingName)` on every
   production vault, with the beacon batch as its predecessor, so the timelock
   refuses to execute it first. It covers a fixed number of leading rows of each
   chain's token table (`TOKEN_COUNT`, tMSTR to tDIS), so its id does not move
   when a table grows; a token added later gets its own `setUnderlying`
   operation. `ticker` is `TokenConfig.underlying` (e.g. `NVDA`) and
   `underlyingName` is `TokenConfig.underlyingName`, the issuer's name without
   any ST0x suffix (e.g. `NVIDIA Corporation`), never `TokenConfig.symbol` /
   `TokenConfig.name`, which hold the initialized ERC-20 values. Its pre-flight
   requires every vault's live symbol to be `"t" + ticker` and the timelock to
   own every vault. Both tokens rename at this step, together: the wrapper goes
   from `wt<TICKER>` to `<TICKER>s`. **Precondition:** do not schedule this step
   until st0x.liquidity, st0x.pricing and st0x-oracle-server accept both
   `wt<TICKER>` and `<TICKER>s` in production, and the st0x.registry token lists
   carry the new symbols and names. Services that match the `wt` prefix would
   otherwise reject every renamed token. The script enforces this: it refuses
   unless `LibUnderlyingNamingRollout.DOWNSTREAM_ACCEPTS_NEW_SYMBOLS` is set.
   RAI-4172 set it: st0x.liquidity accepts both symbols from release v1.29.0,
   st0x.pricing and st0x-oracle-server never read an on-chain `symbol()`, and
   the registry lists keep `symbol` as `wt<TICKER>` and carry the new values as
   `nextSymbol` / `nextName`. The flag's NatSpec links the evidence. It also
   refuses a row whose ticker is not 1 to 16 of `A-Z`, `0-9` and `.`, or whose
   name is empty, has a `"`, `\` or control byte, or already ends in the ST0x
   suffix. A rename cannot be reverted to the initialized metadata:
   `setUnderlying` overwrites the stored ERC-20 name and symbol and rejects
   empty values. The Safe can still `cancel` the operation during its delay.

4. Execute each matured batch with `20261021-execute-underlying-naming`
   `execute()` from the CI deploy key, one operation per dispatch. On HyperEVM
   the rename batch needs more gas than a small block holds, so enable big
   blocks for the deploy key (`manual-hyperevm-big-blocks`) before executing it
   there. After the rename batch executes, the Safe signs `run-script`
   `20261021-execute-underlying-naming` `run()`. It writes the execution's
   record, and until it lands the root line stays at the rename schedule and
   every later migration on that chain refuses.

After the beacon batch, the in-use receipt-vault beacon serves a vault that
initializes only from the ConfigRegistry (rain-vats 0.2.12, config V3). The
deployers that make a `BeaconProxy` on that beacon with a V2 config (the 0.1.1
unified deployer and Base's V1 beacon-set path) then revert
`UnknownConfigVersion`. New listings must move to the V6 factory path of the
registry release before step 2 runs on a chain.

The beacon batch leaves the chain's receipt beacon on its current
implementation. The current-source orchestrator's vault-logic check requires
that beacon to serve `LibProdDeployCurrent.STOX_RECEIPT`, so upgrading the
orchestrator to it needs a receipt-beacon upgrade first, or every token halts
mint and burn. The live 0.1.30 orchestrator does not check the in-use beacons.

After the beacon batch, every new vault on a beacon that serves this
implementation must be initialized nameless with an asset id (RAI-4373): its
`initialize` reverts unless the config's name and symbol are empty and its
metadata is `LibAssetId.encodeMetadata(assetId)` with a non-empty id. The hook
is init-only, so live tokens are unaffected and report `assetId() == ""`.

**V6 listings are deployed nameless.** A V6 token's address commits to its asset
id, region, authority and beacon names, not to its name or symbol. It deploys
with an empty name and symbol. Its owner is the RBAC owner of its region, which
`Deploy.preDeployCheck` requires to be the Zoltu-deployed
`LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK` (not the per-Safe timelocks that
own the live tokens). For every beacon and token suite it also requires that
timelock to be in its pinned state on the chain
(`LibTimelockInvariants.assertTimelockState` with the chain's Safe as proposer:
code, codehash, 48h delay and roles), since anyone can deploy it with another
proposer bound at construction. Anyone names it from a signed listing
(`nameListing`, below); after that only that timelock renames it, with
`setUnderlying` and the 48h delay. Rollout rule: do not publish a V6 token to
the st0x.registry, activate it in the bots, give it mint traffic, or trade it
until it is named and its `name()` and `symbol()` read back as expected. Until
then the vault reports `""` / `""` and the wrapper `"Wrapped "` / `"w"`, which
the liquidity parser does not accept. A token's address commits to the vault
beacon name, not to the implementation the beacon serves, so `VAULT_BEACON_NAME`
must only ever resolve to a beacon that serves an implementation with the asset
id hook and the `assetId()` getter. `Deploy.preDeployCheck` refuses a token
suite unless the bound vault beacon serves
`LibProdDeployCurrent.STOX_RECEIPT_VAULT`. Never roll a V6 vault beacon back to
an implementation without the hook: the asset ids are public, so any undeployed
pinned row could then be deployed with no asset id, forever.

**Naming V6 tokens from a signed listing.** `nameListing` on a V6 token takes
its asset id, ticker and underlying name, a proof, a root and a signature, and
sets the ticker and name as `setUnderlying` does, once. It reverts unless the
token has that asset id and no ticker or name yet, the leaf of the token's own
address and the three fields is in the root, and the listing signer signed the
root. The leaf is OpenZeppelin's `StandardMerkleTree` leaf of
`(address, string, string, string)`. The digest (`LibListing.digest`) is EIP-712
with no chain id and no verifying contract, and a V6 token's address is the same
on every chain, so one signature names the same tokens on every chain, including
chains added later.

- **The signer binding.** `nameListing` reads `st0x.listing-signer.v1` from the
  `ConfigRegistry` under `LibListing.LISTING_AUTHORITY`, the governance timelock
  itself, at every call. Only the timelock writes under it, so binding or
  rotating the signer is a timelock operation: the Safe schedules
  `registerV5(LISTING_AUTHORITY, LISTING_SIGNER_NAME, "address", abi.encode(signer), "")`
  on the registry, and anyone executes it after 48h. The timelock never approves
  a registry delegate: a delegate could rebind at once. Operations never expire,
  so before a bind or rotation check that no other pending operation targets the
  registry or the timelock itself, and cancel abandoned binds. The signer key
  signs listing roots and nothing else.
- **Stale roots and a lost key.** A signed root never expires: a leaf can still
  name a fresh token of its asset id on a new chain after the issuer renamed.
  Rotating the signer on a chain retires every root the old key signed there;
  sign the current roots again with the new key. A compromised key can name
  unnamed V6 tokens with any name and symbol, which also feeds the mint
  weighting's price key (`symbol()`); named tokens refuse. The response is to
  rotate the signer and rename the affected tokens with `setUnderlying`, 48h
  each.
- **Deploy and name in one transaction.** Send Multicall3
  (`0xcA11bde05977b3631167028862bE2a173976CA11`) `aggregate3` with the token's
  factory call and its `nameListing` call, both with `allowFailure = false`, so
  a refused naming deploys nothing. If the token already has code, send the
  `nameListing` call alone. Check Multicall3's code on a chain before its first
  listing.

**The V6 listing.** `LibV6Listing.ROOT` lists the leading 59 production V6 rows
(`LibV6Listing.ROW_COUNT`) and the two test tokens. It is frozen: an edit to
those rows refuses (`V6ListingMoved`). `script/BuildListing.sol` writes
`listing.json`, which `Git is clean` checks: the root, the EIP-712 digest to
sign, and per row the token, asset id, ticker, name, leaf, proof and the factory
call that deploys the token (`deployTo`, `deployData`). A row added later goes
into a new listing root with its own signature; the frozen root keeps naming its
rows. Once the listing signer is bound on a chain:

1. Signing, once for every chain: the signer maps each row of `listing.json` to
   `[token, assetId, ticker, name]`, in that order, and rebuilds the root with
   OpenZeppelin's
   `StandardMerkleTree.of(rows, ["address","string","string","string"])`. It
   checks each asset id, ticker and name against the st0x.registry entry of the
   live token with that asset id, and the five rows sourced from issuers (IBHG,
   RKLB, BIRD, SNES and DIS) and the two test rows against `LibProdTokenConfig`.
   It checks each token address by deriving it from the asset id with the token
   params, not from the registry, which lists no V6 token before it is named. It
   computes the digest from that root (domain name `ST0x Listing`, version `1`,
   no chain id and no verifying contract; struct `Listing(bytes32 root)`),
   checks it equals the `digest` of `listing.json`, and signs it with the
   listing key. The signature is `r || s || v` with a low `s` and `v` 27 or 28,
   and it is kept in the repository next to `ROOT`, with a test that it recovers
   to the signer.
2. Per token: check that the signature recovers to the signer bound on the
   chain, run the token suite's pre-flight as a dry run, then from any account
   send Multicall3 `aggregate3` with the row's `deployTo`/`deployData` call and
   its `nameListing(assetId, ticker, name, proof, root, signature)` call, both
   with `allowFailure = false`. If the token already has code, send the
   `nameListing` call alone.
3. Check that `assetId()` is the row's asset id, `symbol()` is `"t"` + ticker,
   and `name()` is the name + `" (ST0x)"`.

**Root-line order.** Every script is a migration on the root line, and each one
sits onto exactly one predecessor. On each chain the naming rollout runs only
after these have landed, in this order: the V5 backfill
(`20261030-backfill-migration-registry-v5`), the beacon initial owner bind
(`20261022-bind-beacon-initial-owner`), the orchestrator admin move
(`20261006-orchestrator-admin-to-timelock`), and the Safe-owned Base vault
handover (`20261103-hand-safe-owned-base-vaults-to-timelock`). Then come the
beacon schedule, the rename schedule, the execution and its record, and then the
service-signer revoke
(`20261109-schedule-revoke-service-signer-deposit-withdraw` and its execute). V6
tokens are named from the signed listing, which is no migration. While the
rollout is in flight (two 48h delays), no other migration can land on that
chain. The revoke holds the line too, from its schedule record to its execute
record, and its execute waits for minting and redemption to run through the
orchestrator, so the Safe schedules the revoke only once that precondition
holds. An urgent migration in that window needs a new script declared onto the
current head, and a reviewed PR that re-declares the remaining naming scripts
onto it.

**Revoking the service signer's vault roles.** The service signer
(`LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C`) loses `DEPOSIT` and `WITHDRAW`
on the chain's authoriser and keeps `CERTIFY`. The timelock holds
`DEPOSIT_ADMIN` and `WITHDRAW_ADMIN`, so the revoke goes through it.
`LibServiceSignerRevoke` reconstructs the timelock operation. It runs in this
order on every chain:

1. Schedule the revoke batch
   (`20261109-schedule-revoke-service-signer-deposit-withdraw`): one
   `scheduleBatch` of `revokeRole(DEPOSIT, signer)` and
   `revokeRole(WITHDRAW, signer)` on the chain's authoriser, then the Safe's
   root-line record. Its pre-flight requires the timelock to hold both admin
   roles, the signer to hold both roles, and the batch not to be on the timelock
   already.
2. Execute the matured batch with
   `20261109-execute-revoke-service-signer-deposit-withdraw` `execute()` from
   the CI deploy key, then dispatch the same script's `run()` through
   `run-script` for the record-only Safe bundle. **Precondition:** do not
   execute until the service signer's minting and redemption run through the
   orchestrator; the scripts do not check it.

## Invariants

- `LibTimelockInvariants.assertTimelockState(timelock, safe)` — rain-deploy's
  `LibTimelockController.assertTimelockState` at the 48h delay: codehash
  (against the `TimelockController` record of the rain-deploy release this repo
  pins, so the expectation moves only with a deliberate rain-deploy bump, which
  `testPinsMatchDerivedAddresses` then holds to the live addresses), the full
  role model above, no open roles, no root admin outside the timelock itself.
- `LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe,
  timelock)` —
  the single master grant map, parameterised on the admin holder; production
  consumers pass the timelock.
- `LibTokenInvariants.assertUniformOwnership` /
  `LibBeaconInvariants.assertProdBeaconsOwnedBy` /
  `GovernanceTimelockMigration.t.sol` — vault ownership, beacon ownership and
  exclusive `_ADMIN` holding on the timelock, per chain.
- `LibOrchestratorInvariants.assertMintCapsBeaconSet()` /
  `assertMintCapsInstance()` — the mint-caps orchestrator: the beacon is owned
  by the timelock and points at the current implementation; the instance has
  code, the timelock holds the four admin roles, and every `getRoleAdmin` wiring
  is as `initialize` sets it. These are the expected grants only;
  `LibIdealRoles` emits the instance's so the dashboard reports any other
  holder. The live orchestrator keeps `assertBeaconSet` / `assertInstance` while
  both run.

## Orchestrator roles

The orchestrator instance is governed through two dated scripts, each recorded
by the Safe in `rain-deploy`'s `MigrationRegistry` (`LibStoxMigrations`), and
`LibOrchestratorInvariants.assertInstance` asserts exactly the role state the
records imply:

1. `20261006-grant-orchestrator-emergency` — the Safe takes `EMERGENCY_ROLE`
   while it still administers the orchestrator directly; it ran before V5, so
   the backfill records it as history on the root line.
2. `20261006-orchestrator-admin-to-timelock` — `DEFAULT_ADMIN_ROLE` moves from
   the Safe to the timelock, recorded on the root line after
   `20261022-bind-beacon-initial-owner`, which follows the backfill, so the
   registry refuses it on a chain where step 1 has not executed. The Safe-owned
   Base vault handover (`20261103-hand-safe-owned-base-vaults-to-timelock`)
   comes after it.

The root line runs, after the backfill: `20261022-bind-beacon-initial-owner` →
`20261006-orchestrator-admin-to-timelock` →
`20261103-hand-safe-owned-base-vaults-to-timelock` →
`20261021-schedule-underlying-naming-beacons` →
`20261021-schedule-underlying-naming-rename` →
`20261021-execute-underlying-naming` →
`20261109-schedule-revoke-service-signer-deposit-withdraw` →
`20261109-execute-revoke-service-signer-deposit-withdraw`.

Step 1 and the EU authoriser grant were recorded in the V2 registry. The records
are read from V5, so `20261030-backfill-migration-registry-v5` carries them over
as history, per chain, before step 2 can run.

`MINT`, `BURN` and `EMERGENCY` are themselves operations and stay off the
timelock; who may hold them is delay-gated, in both directions. Revoking a
leaked `MINT` or `BURN` key is also a 48h timelock operation; the orchestrator
has no pause, and `EMERGENCY` covers only withdraw, sweep and `setBurnIndex`.
The immediate levers are the key's own `renounceRole`, which the legitimate
holder can still call, and the Safe's direct `CERTIFY` on the authoriser:
forcing a token's certification to expire blocks ordinary transfers of that
token, which stops the orchestrator delivering mints of it, but it freezes every
holder of that token too. The `CERTIFY` lever holds only while the leaked key
cannot certify the token again: the service signer holds `CERTIFY` on the
authoriser as well as `MINT` and `BURN` on the orchestrator, and revoking that
`CERTIFY` is itself a timelock operation. Schedule the timelock revokes (`MINT`
/ `BURN` on the orchestrator, and `CERTIFY` on the authoriser when the leaked
key holds it) at the same time as the Safe expires the certification.

The two steps are separate bundles by choice: the `EMERGENCY` grant is needed
now and is signed on its own, while the admin move is a separate governance
decision, signed once the grant has landed. Before signing step 2, on each
chain, read the rain-org-health dashboard's Role changes tab
(<https://rainlanguage.github.io/rain-org-health/deployments.html>; the
equivalent subgraph queries are in the script's NatSpec):

- cancel every timelock operation still pending against the orchestrator: once
  the timelock is admin, a leftover `grantRole` or `revokeRole` there becomes
  executable by anyone;
- confirm the Safe is the orchestrator's only current `DEFAULT_ADMIN_ROLE`
  holder. Role membership is not enumerable on chain, so the invariants check
  only the Safe and the timelock; a third holder would survive the move with
  immediate admin power.

**Per-role admin roles.** An orchestrator implementation that gives each
operating role its own self-administered admin role (`MINT_ADMIN`, `BURN_ADMIN`,
`EMERGENCY_ADMIN`), installed by a `migrate(admin)` callable only by
`DEFAULT_ADMIN_ROLE`, changes what "admin on the timelock" means: the timelock
must then hold `DEFAULT_ADMIN_ROLE` **and** each `*_ADMIN` role, and the Safe
none of them. Because each `*_ADMIN` administers itself, `DEFAULT_ADMIN_ROLE`
cannot take one back once granted, so `migrate` must be called with the timelock
as `admin`.

- **Step 2 must execute on every chain before that upgrade, or any upgrade of
  the orchestrator beacon or of the receipt-vault or receipt beacon of the
  0.1.30 beacon-set deployer (the set the orchestrator's vault-logic lock
  reads), is scheduled.** If one lands first, step 2 refuses there (its
  pre-flight pins the 0.1.30 implementation, the vault logic it was built
  against and the current role admins), the Safe keeps `DEFAULT_ADMIN_ROLE`, and
  it can call `migrate(safe)` directly, handing itself the self-administered
  `*_ADMIN` roles.
- With step 2 executed, the beacon upgrade and `migrate(timelock)` are both
  timelock operations and go in one `scheduleBatch`. In that implementation
  `MINT_ADMIN` also sets the mint caps and the mint weighting, and `mint`
  reverts while either is unset, so the same batch must set them; otherwise
  minting halts until a second timelock operation lands at least 48h later. Each
  new mint recipient's limit is likewise a 48h timelock operation before its
  first mint.

## Explicitly out of scope (follow-ups)

- **New Base tokens** are V6 listings deployed from this repo (see "V6 listings
  are deployed nameless" above): each takes its owner at initialize from the
  region's RBAC binding, which `Deploy.preDeployCheck` requires to be
  `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK`. `LibInvariants` does not
  check vault ownership: a vault left on the Safe shows only on the
  rain-org-health dashboard.

- **Dedicated canceller** — see the role model above.
