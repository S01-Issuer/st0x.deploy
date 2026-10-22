# ST0x Governance Timelock

## What it is

An **unmodified OpenZeppelin `TimelockController`** (compiled from the
version-locked `@openzeppelin-contracts` 5.6.1 soldeer dependency) that sits
between the token-owner Safe and the privileged surfaces of the ST0x deployment.
Once the governance migration has executed, the timelock is:

- the `owner()` of **every production receipt vault** — so `transferOwnership`,
  `setAuthorizer`, and every `onlyOwner` surface (including owner freezes) is
  delay-gated;
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

No deployed ST0x contract changes for any of this: the owner/admin principal
moves from the Safe to the timelock.

## The mint-caps orchestrator

The mint-caps `ST0xOrchestrator` is a fresh deployment that runs next to the
live orchestrator (`0x3A7387a484d87Aa8bBA45E98AAB401Ce4FBF03E2`) while it is
bootstrapped; minters move over once it is ready. The live orchestrator and its
beacon are not upgraded in place. The new one has its own beacon, because
different code needs a different beacon.

The timelock holds its admin power from the start, so no migration bundle moves
it:

- **Beacon.** `ST0xOrchestratorBeaconSetDeployer`'s constructor creates the
  beacon with `timelockForChainId(block.chainid)` as owner, so there is no
  window in which the deploy key owns it. `upgradeTo` is delay-gated.
- **Instance.** `initialize` grants the timelock `DEFAULT_ADMIN_ROLE`,
  `MINT_ADMIN_ROLE`, `BURN_ADMIN_ROLE` and `EMERGENCY_ADMIN_ROLE`, and nothing
  else. It takes no owner argument, and `deploy()` takes none either, so a
  caller of the permissionless deployer cannot seat an admin of its own. Both
  revert on a chain with no pinned timelock.
- **Operating roles** (`MINT_ROLE`, `BURN_ROLE`, `EMERGENCY_ROLE`) are granted
  by their admin role, so each grant is a scheduled timelock operation. The Safe
  may hold `EMERGENCY_ROLE`; it holds no admin role and neither `MINT_ROLE` nor
  `BURN_ROLE`. The deploy key holds nothing.
- **Configuration.** The mint weighting and the per-minter and per-recipient
  mint limits are `MINT_ADMIN_ROLE` surfaces, so setting or changing them waits
  out the delay too.

Each admin role administers its operating role and itself, so
`DEFAULT_ADMIN_ROLE` cannot grant an admin role: the grants in `initialize` are
the only way a first holder is seated, and losing every holder of one takes a
beacon upgrade to recover.

Bootstrapping is `script/20261011-bootstrap-mint-caps-orchestrator.s.sol`, a
Safe bundle per chain: deploy the implementation and the beacon-set deployer,
`deploy()` the instance, then schedule one timelock batch with the weighting,
the limits, the operating-role grants and the timelock's registry record. The
instance's `DEPOSIT`/`WITHDRAW` grants on the vault authoriser are made by
whichever principal holds `DEPOSIT_ADMIN` / `WITHDRAW_ADMIN` there: directly by
the Safe, or in the batch once the timelock holds them.

## Role model

| Role on the timelock | Holder                                              | Meaning                                                         |
| -------------------- | --------------------------------------------------- | --------------------------------------------------------------- |
| `PROPOSER_ROLE`      | token-owner Safe                                    | schedules operations                                            |
| `CANCELLER_ROLE`     | token-owner Safe (+ dedicated canceller, if pinned) | vetoes a scheduled operation inside the window                  |
| `EXECUTOR_ROLE`      | `address(0)` — i.e. anyone                          | executes once the delay elapses                                 |
| `DEFAULT_ADMIN_ROLE` | the timelock itself                                 | role changes are themselves timelocked (OZ self-administration) |

- **Execution is permissionless.** `EXECUTOR_ROLE` is granted to `address(0)`,
  which OZ's `onlyRoleOrOpenRole` reads as "open to everyone", so once the delay
  has run ANYONE may execute a scheduled operation. The operator cannot censor a
  matured operation, and the Safe executes as a member of the public rather than
  by privilege. `cancel()` has no open-role path in OZ, so vetoing stays
  privileged.
- **Operations never expire.** OZ keeps a matured operation executable
  indefinitely. With open execution that means a scheduled-then-abandoned
  operation can be executed by anyone, at any later time. An operation that must
  not run has to be CANCELLED, not merely left unexecuted.
- **Min delay: 48 hours** (`LibTimelockInvariants.TIMELOCK_MIN_DELAY`). Changing
  it is a timelocked `updateDelay` operation and must update the pin in the same
  operational window.
- **The CI deploy key holds nothing.** The deploy passes `admin = address(0)`,
  so the constructor grants the deployer no role; the deploy script's post-state
  asserts it.
- **No open roles.** OZ treats a zero-address grantee as "role open to
  everyone"; `assertTimelockState` rejects that on every lifecycle role.
- **Dedicated canceller.** The OZ constructor grants cancellership to proposers,
  so the Safe can always cancel. A separate canceller principal is optional and
  lives in `LibTimelockInvariants.TIMELOCK_CANCELLER`: while that pin is
  `address(0)` no extra canceller is expected, and while it is non-zero
  `assertTimelockState` asserts the grant. Provisioning one is itself a
  timelocked operation — schedule `grantRole(CANCELLER_ROLE, canceller)` on the
  timelock and set the constant in the same operational window. It cannot be set
  in the constructor, which takes no canceller argument.

## Addresses

The timelock is deployed via the **Zoltu deterministic factory**: its address is
a pure function of its creation code (OZ creation bytecode + constructor args).
The chain's Safe is a constructor arg, so each chain gets a distinct,
precomputable address —
`LibTimelockInvariants.expectedTimelockAddress(chain's Safe)`.

Constants (in `src/lib/LibTimelockInvariants.sol`) that scripts and invariants
target:

| Constant                             | Holds                                     |
| ------------------------------------ | ----------------------------------------- |
| `STOX_GOVERNANCE_TIMELOCK`           | the Base timelock                         |
| `STOX_GOVERNANCE_TIMELOCK_ETHEREUM`  | the Ethereum timelock                     |
| `STOX_GOVERNANCE_TIMELOCK_HYPEREVM`  | the HyperEVM timelock                     |
| `STOX_GOVERNANCE_TIMELOCK_ROBINHOOD` | the Robinhood Chain timelock              |
| `STOX_GOVERNANCE_TIMELOCK_BSC`       | the BNB Smart Chain timelock              |
| `TIMELOCK_CANCELLER`                 | the dedicated canceller (zero while none) |

Every pin is written with its chain arm, derived from the frozen creation
bytecode and that chain's Safe pin before any deploy —
`testPinsMatchDerivedAddresses` asserts each equality unconditionally, so a
wrong or zeroed pin cannot survive CI. A zero pin is never a legitimate phase:
every consumer (the deploy pre-flight, the migration authoring,
`assertTimelockState`) refuses it as a reverted or never-hydrated arm rather
than proceeding against a wrong address. All five timelocks are live at their
pins.

## Rollout (per chain: Base, Ethereum, HyperEVM, Robinhood Chain, BNB Smart Chain)

1. **Deploy** — Actions → `manual-broadcast` →
   `20260729-deploy-governance-timelock`. One dispatch covers every governed
   chain: the script iterates `networks()`, skips-with-assert any chain already
   carrying its timelock, and the CI deploy key broadcasts the rest — each
   landing at its derived address, fully configured by its constructor.
2. **Author the migration bundle** — Actions → `run-script` →
   `20260729-migrate-governance-to-timelock`, network `base` / `ethereum` /
   `hyperevm` / `robinhood` / `bsc`. Emits the Safe Tx Builder JSON
   (`out/20260729-governance-timelock-migration-<chainid>.json`) after a full
   pre-flight, simulation, post-state assertion, and an end-to-end schedule →
   48h → execute proof on the fork. The logged MultiSend `SafeTxHash` is the
   signer cross-check.
3. **Sign + execute** — import the CI-authored artifact into the Safe UI (never
   a locally generated JSON). Before signing, each signer runs the local
   integrity check against a live fork —
   `forge script script/20260729-migrate-governance-to-timelock.s.sol --sig 'verify(string)' <downloaded.json> --rpc-url <network>`
   — which re-derives the bundle from current chain state, asserts the artifact
   matches byte-exactly, and prints the MultiSend `SafeTxHash` at the live nonce
   to cross-check in the Safe UI. Then execute. The bundle is atomic: 7 `_ADMIN`
   grants to the timelock → N vault `transferOwnership` → one beacon
   `transferOwnership` per in-use beacon (four) → 7 Safe renounces.
4. **Post-execution flip** — every production invariant asserts the timelock
   exactly: vault owner (`LibTokenInvariants.assertAll` / `LibInvariants`),
   beacon owner (`LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock`,
   `LibOrchestratorInvariants.assertBeaconSet`) and `_ADMIN` holder
   (`LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe, timelock)`).
   The migration has executed on all five chains, so this is the current state.

`GovernanceTimelockMigration.t.sol` pins the governed state on every chain. The
migration script's own tests rewind each fork to the pre-migration state with
the timelock's powers, so the script stays re-dispatchable and proven.

## Rehearsing the timelock

The rehearsal exercises the timelock end-to-end. The rehearsed operation is
`timelock.updateDelay(TIMELOCK_MIN_DELAY)` — re-setting the delay to the value
it already holds. It is a no-op, it targets the timelock rather than any
production contract, and OZ rejects `updateDelay` from any caller other than the
timelock itself, so it can only happen via the full schedule → delay → execute
path.

Stages 1–3 are Safe actions, dispatched via `Actions → run-script`:

1. `20260813-timelock-rehearsal-schedule` — schedule the no-op.
2. `20260813-timelock-rehearsal-cancel` — cancel it. Proves the veto works and
   that the same operation id becomes schedulable again afterwards.
3. `20260813-timelock-rehearsal-schedule` again — re-dispatching the same script
   IS the re-propose stage. `cancel` deregisters the operation, so the identical
   one becomes schedulable again; there is no separate operation, so there is no
   separate script.

Then wait out the delay and execute. Execution is **not** a Safe action: the
executor role is open, so anyone may execute. `Actions → manual-broadcast` →
`20260813-execute-timelock-operations` does it from the CI deploy key, which
holds no role on the timelock.

Each stage refuses to author a bundle whose call would revert: cancelling
nothing, or scheduling something already scheduled, fails at authoring time
rather than in the Safe.

**The execution stage is one-shot.** `REHEARSAL_SALT` is a constant, so the
operation id is fixed per chain, and OZ keeps an executed operation registered
forever (`_execute` writes `DONE_TIMESTAMP`; only `cancel` clears it). Once the
rehearsal has been executed on a chain, every later
`20260813-timelock-rehearsal-schedule` dispatch there refuses with
`RehearsalAlreadyScheduled`, and the fork tests that drive scheduling report
`SPENT` and stop asserting. Cancel-and-re-propose can be repeated freely;
rehearsing again _after_ an execution needs a new salt, i.e. a new dated
rehearsal.

## Operating under the timelock

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

Operational scripts that author such bundles follow the dated `run-script`
pattern: they build the schedule/execute calldata against
`LibTimelockInvariants` constants, and each script's simulation includes the
same warp-and-execute loop proof the migration script uses.

**Key invariant for script authors**: the Safe cannot call `onlyOwner` /
`_ADMIN`-gated functions directly. Any script that authors a Safe bundle
targeting those surfaces must target the timelock instead, resolved via
`LibTimelockInvariants.timelockForChainId(block.chainid)`.

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
  `assertMintCapsInstance(safe)` — the mint-caps orchestrator: the beacon is
  owned by the timelock and points at the current implementation; the timelock
  holds the four admin roles and no operating role; the Safe holds no admin
  role, `MINT_ROLE` or `BURN_ROLE`; the deploy key holds nothing; and every
  `getRoleAdmin` wiring is as `initialize` sets it. The live orchestrator keeps
  `assertBeaconSet` / `assertInstance` while both run.

## Orchestrator roles

The orchestrator instance is governed through two dated scripts, each recorded
by the Safe in `rain-deploy`'s `MigrationRegistry` (`LibStoxMigrations`), and
`LibOrchestratorInvariants.assertInstance` asserts exactly the role state the
records imply:

1. `20261006-grant-orchestrator-emergency` — the Safe takes `EMERGENCY_ROLE`
   while it still administers the orchestrator directly, and records the
   governance-timelock migration (as history) and the grant.
2. `20261006-orchestrator-admin-to-timelock` — `DEFAULT_ADMIN_ROLE` moves from
   the Safe to the timelock, recorded onto the grant, so the registry refuses it
   on a chain where step 1 has not executed.

Step 1 and the EU authoriser grant were recorded in the V2 registry. The records
are read from V3, so `20261022-backfill-migration-registry-v3` carries them over
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
  the orchestrator, receipt-vault or receipt beacon, is scheduled.** If one
  lands first, step 2 refuses there (its pre-flight pins the 0.1.30
  implementation, the vault logic it was built against and the current role
  admins), the Safe keeps `DEFAULT_ADMIN_ROLE`, and it can call `migrate(safe)`
  directly, handing itself the self-administered `*_ADMIN` roles.
- With step 2 executed, the beacon upgrade and `migrate(timelock)` are both
  timelock operations and go in one `scheduleBatch`. In that implementation
  `MINT_ADMIN` also sets the mint caps and the mint weighting, and `mint`
  reverts while either is unset, so the same batch must set them; otherwise
  minting halts until a second timelock operation lands at least 48h later. Each
  new mint recipient's limit is likewise a 48h timelock operation before its
  first mint.

## Explicitly out of scope (follow-ups)

- **New Base tokens** are deployed by the sft-ops CD pipeline, not by a script
  here. It must hand each new vault to `STOX_GOVERNANCE_TIMELOCK`
  (`transferOwnership`); a vault left on the Safe fails the token and governance
  invariants as soon as it is pinned.

- **Dedicated canceller** — see the role model above.
