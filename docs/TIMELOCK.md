# ST0x Governance Timelock

## What it is

An **unmodified, pre-audited OpenZeppelin `TimelockController`** (compiled from
the version-locked `@openzeppelin-contracts` 5.6.1 soldeer dependency) that sits
between the token-owner Safe and the privileged surfaces of the ST0x deployment.
After the migration executes, the timelock is:

- the `owner()` of **every production receipt vault** — so `transferOwnership`,
  `setAuthorizer`, and every `onlyOwner` surface (including owner freezes) is
  delay-gated; and
- the **sole holder of the authoriser's seven `_ADMIN` roles** (`DEPOSIT_ADMIN`,
  `WITHDRAW_ADMIN`, `CERTIFY_ADMIN`, `CONFISCATE_SHARES_ADMIN`,
  `CONFISCATE_RECEIPT_ADMIN`, `SCHEDULE_CORPORATE_ACTION_ADMIN`,
  `CANCEL_CORPORATE_ACTION_ADMIN`) — so adding or removing grants on the
  authoriser is delay-gated.

The Safe **keeps its three direct action roles** (`DEPOSIT`, `WITHDRAW`,
`CERTIFY`) and the service signer keeps its operational grants: day-to-day
operations are NOT timelocked. Only admin power is.

No deployed ST0x contract changes for any of this — the timelock is purely a
deployment-config choice (the owner/admin principal moves from the Safe to the
timelock). That keeps the audited contract set untouched.

## Role model

| Role on the timelock | Holder                                                 | Meaning                                                         |
| -------------------- | ------------------------------------------------------ | --------------------------------------------------------------- |
| `PROPOSER_ROLE`      | token-owner Safe                                       | schedules operations                                            |
| `CANCELLER_ROLE`     | token-owner Safe (+ dedicated canceller, once decided) | vetoes a scheduled operation inside the window                  |
| `EXECUTOR_ROLE`      | token-owner Safe                                       | executes once the delay elapses                                 |
| `DEFAULT_ADMIN_ROLE` | the timelock itself                                    | role changes are themselves timelocked (OZ self-administration) |

- **Min delay: 48 hours** (`LibTimelockInvariants.TIMELOCK_MIN_DELAY`). Changing
  it is a timelocked `updateDelay` operation and must update the pin in the same
  operational window.
- **The CI deploy key holds nothing, ever.** The deploy passes
  `admin = address(0)`, so the constructor grants the deployer no role — there
  is no configuration window and nothing to revoke. The deploy script's
  post-state proves it.
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
a pure function of its creation code (OZ creation bytecode + constructor args).
The chain's Safe is a constructor arg, so each chain gets a distinct,
precomputable address —
`LibTimelockInvariants.expectedTimelockAddress(chain's Safe)`.

Constants (in `src/lib/LibTimelockInvariants.sol`) that future scripts and
invariants target:

| Constant                            | Holds                                     |
| ----------------------------------- | ----------------------------------------- |
| `STOX_GOVERNANCE_TIMELOCK`          | the Base timelock                         |
| `STOX_GOVERNANCE_TIMELOCK_ETHEREUM` | the Ethereum timelock                     |
| `STOX_GOVERNANCE_TIMELOCK_HYPEREVM` | the HyperEVM timelock                     |
| `TIMELOCK_CANCELLER`                | the dedicated canceller, once provisioned |

Each pin is `address(0)` until that chain's deploy broadcast has run and the pin
PR has recorded the address. `timelockForChainId` returns the pin, so an
unhydrated chain reads as `address(0)` and every consumer that requires a
timelock refuses rather than proceeding against a wrong address.
`testPinsMatchDerivedAddressesOnceHydrated` ties every hydrated pin to the
derivation, so a pin PR cannot record a wrong address.

## Rollout (per chain: Base, Ethereum, HyperEVM)

1. **Deploy** — Actions → `manual-broadcast` →
   `20260729-deploy-governance-timelock`, network `base` / `ethereum` /
   `hyperevm`. CI deploy key broadcasts; the timelock lands at the derived
   address, fully configured by its constructor.
2. **Pin PR** — hydrate that chain's
   `LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK*` with the logged address.
3. **Author the migration bundle** — Actions → `run-script` →
   `20260729-migrate-governance-to-timelock`, network `base` / `ethereum` /
   `hyperevm`. Emits the Safe Tx Builder JSON
   (`out/20260729-governance-timelock-migration-<chainid>.json`) after a full
   pre-flight, simulation, post-state assertion, and an end-to-end schedule →
   48h → execute proof on the fork. The logged MultiSend `SafeTxHash` is the
   signer cross-check.
4. **Sign + execute** — import the CI-authored artifact into the Safe UI (never
   a locally generated JSON), verify the hash, execute. The bundle is atomic: 7
   `_ADMIN` grants to the timelock → N vault `transferOwnership` → 7 Safe
   renounces.
5. **Post-execution flip PR** — mark the migration script
   `**EXECUTED YYYY-MM-DD.**`, repoint the strict uniform-ownership invariants
   (`LibInvariants.assertAll`, `LibTokenInvariants` consumers,
   `StoxProdV2`/`LibInvariants` fork tests, cross-chain parity) from the Safe to
   the timelock, and retire the spent branch of the migration-window suite.

The forcing function: `GovernanceTimelockMigration.t.sol` accepts
Safe-or-timelock per surface until **2026-10-01T00:00:00Z**, then demands the
timelock. An unfinished rollout red-lines cron past that date.

## Operating under the timelock (future governance actions)

Every admin action becomes two Safe transactions separated by ≥48h:

1. **Schedule**: Safe → `timelock.schedule(target, 0, data, 0, salt, 172800)`
   where `data` is the admin call (e.g.
   `authoriser.grantRole(DEPOSIT, newSigner)`,
   `vault.setAuthorizer(newAuthoriser)`, `vault.transferOwnership(newOwner)`).
   Batch multiple calls with `scheduleBatch`.
2. **Wait** out the delay. Anyone can watch pending operations via
   `CallScheduled` events; the Safe (or the dedicated canceller, once
   provisioned) can `cancel(id)` during the window.
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

## Invariants

- `LibTimelockInvariants.assertTimelockState(timelock, safe)` — codehash
  (derived from the compiled OZ dependency, so a dependency bump surfaces as
  drift against the live deployment), 48h min delay, the full role model above,
  no open roles, no root admin outside the timelock itself.
- `LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe,
  timelock)` —
  the single master grant map, parameterised on the admin holder; post-migration
  consumers pass the timelock.
- `LibTokenInvariants.assertUniformOwnershipMigration` /
  `GovernanceTimelockMigration.t.sol` — the migration window + deadline (see
  above).

## Explicitly out of scope (follow-ups)

- **Beacon ownership.** The upgrade beacons remain Safe-owned. Moving them under
  the timelock is the same one-call-per-beacon `transferOwnership` pattern and
  can reuse this machinery wholesale, but it gates contract UPGRADES (not token
  admin) and deserves its own decision + rollout.
- **Dedicated canceller** — see the role model above.
