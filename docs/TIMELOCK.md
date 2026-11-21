# ST0x Governance Timelock

An unmodified OpenZeppelin `TimelockController` sits between the token-owner
Safe and the privileged surfaces of the deployment. No ST0x contract changes for
it: the owner/admin principal is the timelock instead of the Safe.

## What it gates

A surface held by the timelock is delay-gated:

- vault `owner()`: `transferOwnership`, `setAuthorizer`, `setUnderlying`, owner
  freezes and every other `onlyOwner` surface;
- upgrade beacon `owner()`: `upgradeTo`;
- the authoriser's `_ADMIN` roles: granting or revoking the operating roles;
- the orchestrator's admin roles: granting or revoking `MINT`, `BURN` and
  `EMERGENCY`, and the `MINT_ADMIN_ROLE` mint-limit and weighting settings.

Operating roles (`DEPOSIT`, `WITHDRAW`, `CERTIFY`, `MINT`, `BURN`, `EMERGENCY`)
are not timelocked; only who may hold them is.

Beacons are gated with the surfaces they serve: a beacon owner can `upgradeTo`
an implementation that rewrites vault ownership and authoriser wiring, so a
delay on those surfaces is bypassable while the beacon is not delay-gated too.

Which contracts the timelock holds on which chain is asserted by the invariant
libraries below and reported from `privileged-addresses.json`.

## Role model

| Role on the timelock | Holder                                      | Meaning                                |
| -------------------- | ------------------------------------------- | -------------------------------------- |
| `PROPOSER_ROLE`      | token-owner Safe                            | schedules operations                   |
| `CANCELLER_ROLE`     | token-owner Safe, plus `TIMELOCK_CANCELLER` | cancels a pending operation            |
| `EXECUTOR_ROLE`      | `address(0)`, i.e. anyone                   | executes once the delay elapses        |
| `DEFAULT_ADMIN_ROLE` | the timelock itself                         | role changes are themselves timelocked |

- **Execution is open.** OZ reads an `EXECUTOR_ROLE` grant to `address(0)` as
  open to everyone, so anyone may execute a matured operation. `cancel` has no
  open path, so cancelling stays privileged.
- **Operations never expire.** A matured operation stays executable by anyone
  indefinitely. An operation decided against must be cancelled.
- **Min delay** is `LibTimelockInvariants.TIMELOCK_MIN_DELAY`. Changing it is a
  timelocked `updateDelay`.
- **The deployer holds nothing.** The constructor passes `admin = address(0)`.
- **No open roles** other than execution: `assertTimelockState` rejects a
  zero-address grantee on every other role.
- **Dedicated canceller.** OZ makes every proposer a canceller. An extra
  canceller is `LibTimelockInvariants.TIMELOCK_CANCELLER`; while it is
  `address(0)` none is expected, otherwise `assertTimelockState` asserts the
  grant. Adding one is a timelocked `grantRole(CANCELLER_ROLE, canceller)`.

## Operations

An admin action is two calls separated by at least the min delay:

1. The Safe calls `schedule(target, value, data, predecessor, salt, delay)` (or
   `scheduleBatch`), where `data` is the admin call.
2. After the delay, anyone calls `execute` (or `executeBatch`) with identical
   arguments.

The operation id is a hash of the arguments, so a fixed salt gives a fixed id. A
non-zero `predecessor` makes execution wait on that operation. A reverted
`executeBatch` leaves the operation ready with its delay spent; it can be
executed again. A proposer or canceller can `cancel(id)` any pending operation.

The Safe cannot call a timelock-held surface directly. Scripts resolve the
timelock only via `LibTimelockInvariants.timelockForChainId(block.chainid)`.

## Addresses

The timelock is deployed through the Zoltu factory, so its address is a function
of its creation code. The `stox-governance-timelock` suite reads its initial
proposer from the `ConfigRegistry` under `TIMELOCK_INITIAL_PROPOSER_NAME`, so
its creation code and address are chain-invariant; its constructor reverts
while that name is unset. A timelock that takes the Safe as a constructor
argument sits at `LibTimelockInvariants.expectedTimelockAddress(safe)`.

Per-chain timelock addresses are the constants in `LibTimelockInvariants`;
`testPinsMatchDerivedAddresses` re-derives each one, and every consumer refuses
a zero pin.

## Mint-caps orchestrator

The mint-caps `ST0xOrchestrator` reads its admin from the `ConfigRegistry`
under `LibRegistryAuthority.ROOT_AUTHORITY`, so its creation code is
chain-invariant and no bundle moves admin power:

- **Beacon.** `ST0xOrchestratorBeacon` is owned by
  `LibStoxConfig.beaconInitialOwner()`; its constructor reverts while that
  binding is unset or zero.
- **Instance.** A registry beacon proxy over the beacon bound under
  `LibStoxConfig.ORCHESTRATOR_BEACON_NAME`. `initialize` takes no admin
  argument and grants the registry-bound initial admin `DEFAULT_ADMIN_ROLE`,
  `MINT_ADMIN_ROLE`, `BURN_ADMIN_ROLE` and `EMERGENCY_ADMIN_ROLE`; it reverts
  while the binding is unset, not an `address`, or zero.
- Each admin role administers its operating role and itself, so
  `DEFAULT_ADMIN_ROLE` cannot grant an admin role: `initialize` is the only way
  a first holder is seated.

## Invariants

- `LibTimelockInvariants.assertTimelockState(timelock, safe)`: codehash, the
  role model above, no open roles, no admin outside the timelock.
- `LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe, timelock)`:
  the grant map, parameterised on the admin holder.
- `LibTokenInvariants.assertUniformOwnership`,
  `LibBeaconInvariants.assertProdBeaconsOwnedBy`: vault and beacon ownership.
- `LibOrchestratorInvariants.assertMintCapsBeaconSet` /
  `assertMintCapsInstance`: the mint-caps beacon owner and implementation, and
  the instance's admin roles and role-admin wiring.

Which migrations have run on which chain is in `migrations.json`.
