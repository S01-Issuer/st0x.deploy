# ST0x Governance Timelock

## What it is

An **unmodified OpenZeppelin `TimelockController`** (compiled from the
version-locked `@openzeppelin-contracts` 5.6.1 soldeer dependency) that sits
between the token-owner Safe and the privileged surfaces of the ST0x deployment.
Once the governance migration has executed, the timelock is:

- the `owner()` of **every production receipt vault** — so `transferOwnership`,
  `setAuthorizer`, and every `onlyOwner` surface (including owner freezes) is
  delay-gated;
- the `owner()` of the chain's **three in-use upgrade beacons** (receipt,
  receipt vault, wrapped token vault) — so `upgradeTo` is delay-gated; and
- the **sole holder of the authoriser's seven `_ADMIN` roles** (`DEPOSIT_ADMIN`,
  `WITHDRAW_ADMIN`, `CERTIFY_ADMIN`, `CONFISCATE_SHARES_ADMIN`,
  `CONFISCATE_RECEIPT_ADMIN`, `SCHEDULE_CORPORATE_ACTION_ADMIN`,
  `CANCEL_CORPORATE_ACTION_ADMIN`) — so adding or removing grants on the
  authoriser is delay-gated.

Every production token proxies through those three beacons, and a beacon owner
can `upgradeTo` a new implementation for all of them in a single transaction, so
beacon ownership moves to the timelock in the same atomic bundle as vault
ownership and the authoriser admin roles, under the same deadline.

The Safe **keeps its three direct action roles** (`DEPOSIT`, `WITHDRAW`,
`CERTIFY`) and the service signer keeps its operational grants: day-to-day
operations are NOT timelocked. Only admin power is.

No deployed ST0x contract changes for any of this: the owner/admin principal
moves from the Safe to the timelock.

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

Every pin equals `expectedTimelockAddress(chain's Safe)`, derived from the
frozen creation bytecode and that chain's Safe pin;
`testPinsMatchDerivedAddresses` asserts each equality. A zero pin is never
legitimate: every consumer (the deploy pre-flight, the migration authoring, the
migration-window suite) refuses it rather than proceeding against a wrong
address.

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
   grants to the timelock → N vault `transferOwnership` → 3 beacon
   `transferOwnership` → 7 Safe renounces.

`GovernanceTimelockMigration.t.sol` accepts Safe-or-timelock per surface until
**2026-10-01T00:00:00Z**, then demands the timelock. An unfinished rollout
red-lines cron past that date.

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
2. **Wait** out the delay. Anyone can watch pending operations via
   `CallScheduled` events; the Safe (or the dedicated canceller, if pinned) can
   `cancel(id)` during the window.
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

- `LibTimelockInvariants.assertTimelockState(timelock, safe)` — codehash
  (against the pinned `TIMELOCK_RUNTIME_CODEHASH` literal of the frozen
  `TIMELOCK_CREATION_CODE` generation, so a compiler-settings or dependency
  change cannot drift the expectation away from the live deployment), 48h min
  delay, the full role model above, no open roles, no root admin outside the
  timelock itself.
- `LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe,
  timelock)` —
  the single master grant map, parameterised on the admin holder; post-migration
  consumers pass the timelock.
- `LibTokenInvariants.assertUniformOwnershipMigration` /
  `LibBeaconInvariants.assertProdBeaconsOwnershipMigration` /
  `GovernanceTimelockMigration.t.sol` — the migration window + deadline (see
  above), over vault ownership, beacon ownership and `_ADMIN` holding.
