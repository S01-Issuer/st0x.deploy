# V4 upgrade runbook

End-to-end operational sequence for landing the V4 authoriser + corp-actions
upgrade. Each numbered step is a single discrete operator action — a workflow
dispatch, a PR merge, an on-device hardware signature, etc.

For the underlying mechanics (invariant libs, script-authoring lifecycle,
generic post-run process, naming + status conventions, migration-window
invariant pattern), see [`OPERATIONAL_SCRIPTS.md`](OPERATIONAL_SCRIPTS.md). This
file is the V4-specific runbook only.

The V4 impls (all 10, including both authorizer impls and the corp-actions
facet) are **already Zoltu-deployed on Base** and pinned + live-asserted by
`StoxProdV4.t.sol` on main, so there is no impl-deploy phase here. Only the
authoriser _clone_ (non-deterministic address) and the Safe-signed upgrade
bundle remain.

---

## Prerequisites

- GitHub access with `workflow_dispatch` permission on the repo.
- Hardware wallet provisioned with one of the 6 ST0x token-owner Safe signer
  keys (need 3 signers for the single Safe-routed bundle in step 5).
- The `rainlang.eth` wallet, used once in step 2 only.

There is exactly **one Safe signing ceremony** in this runbook (step 5). The
clone deploy + grant wiring (step 3) broadcasts from the CI deploy key, and the
beacon-ownership migration (step 2) broadcasts from `rainlang.eth`.

---

## 1 — Merge the migration stack

Merge in stack order:
[#233](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/233)
(migration-invariant lib + beacon-owner pin) →
[#242](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/242)
(CI-broadcast authoriser clone deploy) →
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197) (V4
upgrade + swap script + post-swap state pin).

All three merge **before** anything runs on-chain — the migration-window
invariants they carry accept both pre- and post-execution live state until their
deadlines, so nothing sits red waiting for ops.

[#211](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/211) (clone
address pin) stays open until step 4 — it's a one-line diff that cannot be
written until the clone address exists. Its `V4AuthoriserCloneNotPinned`
pre-flight revert on the
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197) script is
what blocks step 5 from being dispatched too early; merging
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197) ahead of
it is safe.

---

## 2 — Migrate beacon ownership to the Safe

`script/MigrateBeaconOwners.s.sol` transfers ownership of the three production
beacons from `rainlang.eth` to `STOX_TOKEN_OWNER_SAFE`. Direct EOA broadcast
(single signer, not a Safe bundle), run **locally** with the rainlang.eth
wallet:

```shell
BASE_RPC_URL=<base rpc> \
  forge script script/MigrateBeaconOwners.s.sol \
  --rpc-url base --broadcast --slow --ledger
```

The script pre-flights every beacon's current EOA-owned state, broadcasts 3
`transferOwnership(Safe)` calls, re-asserts `owner() == Safe` post-broadcast,
and proves n+1 reversibility (the Safe can act on each beacon) via simulated
`execTransaction`s.

Verify on Basescan: each beacon's `owner` is now `0xe70d821f…`.

The `BeaconOwnerMigrationPinTest` cron invariant (from
[#233](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/233)) flips
from accepting either owner to enforcing the Safe automatically — no code change
needed. If this step is skipped past the migration deadline in that test, cron
goes red until someone runs it, extends the deadline, or deletes the invariant.

---

## 3 — Deploy + wire the V4 authoriser clone (CI broadcast)

GitHub UI → **Actions** → **manual-broadcast** → **Run workflow**.

- `script`: `20260619-deploy-v4-authoriser-clone`

One workflow dispatch, one broadcast from the CI deploy key
(`secrets.PRIVATE_KEY` — same key as the impl deploys). The script:

1. Deploys the clone via `CloneFactory.clone` with the deploy key as transient
   `initialAdmin`.
2. Grants the 6 operational roles (`DEPOSIT` / `WITHDRAW` / `CERTIFY` × service
   EOA + Safe) per `LibAuthoriserInvariants.expectedGrants()`.
3. Grants all 7 auto-granted `_ADMIN` roles (5 base + 2 corporate-action) to the
   ST0x token-owner Safe.
4. Renounces all 7 from the deploy key, then asserts post-state: every expected
   grant held, Safe holds every admin role, deploy key holds none.

From the **Broadcast script** step log, copy the `Clone: 0x…` line in the
`==== V4 AUTHORISER CLONE DEPLOYED ====` block.

Cross-check on Basescan: `extcodehash` of the clone equals
`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` (already pinned — the
codehash is deterministic from the impl address; only the clone address awaits
this broadcast).

---

## 4 — Pin the clone address ([#211](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/211))

One-line diff:

1. Check out
   [#211](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/211)'s
   branch.
2. In `src/lib/LibProdDeployV4.sol`, replace
   `STOX_PROD_AUTHORISER_V4_CLONE = address(0)` with the clone address from
   step 3. (The codehash constant is already hydrated — no change needed.)
3. Also flip `testAuthoriserV4ClonePlaceholder` in
   `test/src/lib/LibProdDeployV4.t.sol` from the placeholder guard to a
   real-address assertion.
4. Push. Reviewer cross-checks the literal against the broadcast receipt and
   `cast keccak $(cast code <clone> --rpc-url base)` against the pinned
   codehash.
5. Merge.

This clears the `V4AuthoriserCloneNotPinned` pre-flight on the
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197) script —
step 5 is now dispatchable.

---

## 5 — Execute the V4 upgrade (the one Safe ceremony)

GitHub UI → **Actions** → **run-script** → **Run workflow**.

- `script`: `20260623-upgrade-receipt-vaults-to-v4`
- `sig`: `run()`

1. Download artifact `20260623-upgrade-receipt-vaults-to-v4-run()-out`.
2. Capture `SafeTxHash` from the **Run script** step log.
3. Safe UI on Base → ST0x token-owner Safe → **Apps** → **Tx Builder** → drop
   the JSON → **Send Batch**.
4. **Verify the UI's SafeTxHash matches step 2 byte-for-byte.** If not, abort
   and re-dispatch (the Safe nonce moved between authoring and import).
5. 3 signers each: open the queued tx → **Confirm** → approve on hardware device
   → **verify the on-device SafeTxHash matches step 2**.
6. Any signer clicks **Execute**.

Bundle shape: 1 `upgradeTo(V4 impl)` on the receipt-vault beacon + N
`setAuthorizer(<clone>)` calls (one per production receipt vault). After
execution, every vault routes corp-action selectors via fallback delegatecall
and is gated by the V4 clone.

The migration-window pins from
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197)
(`StoxProdV4PostSwap.t.sol`, `20260623-upgrade-receipt-vaults-to-v4.t.sol`) flip
from accepting either authoriser to enforcing the V4 clone automatically.

---

## 6 — Post-execution tidy (non-blocking)

Rolled-up follow-ups; none block the upgrade itself:

- Update `LibAuthoriserInvariants.STOX_PROD_AUTHORISER` to the V4 clone (+ impl
  pin) so the no-arg `assertAll` validates the new live state, and extend
  `expectedGrants()` from 11 to 13 with the two corporate-action admin grants
  (`SCHEDULE_CORPORATE_ACTION_ADMIN` / `CANCEL_CORPORATE_ACTION_ADMIN` → Safe)
  that the V4 clone now carries.
- Update the executed scripts' NatSpec status banners from `**PENDING.**` to
  `**EXECUTED YYYY-MM-DD.**` (+ SafeTxHash for the Safe bundle).
- Collapse the migration-window invariants whose migrations have landed (per
  [`OPERATIONAL_SCRIPTS.md`](OPERATIONAL_SCRIPTS.md) § removal options): the
  beacon-owner pin and the authoriser-swap pins become plain post-state equality
  checks.
- Add the exhaustive-grants check to `LibAuthoriserInvariants` (assert no grants
  exist OUTSIDE `expectedGrants()`, via `RoleGranted`/`RoleRevoked` event-scan
  tooling) — closes the directional-assertion gap for good.

V4 upgrade workstream complete. From here, every script's `assertAll(safe)`
pre-flight on main validates against the new V4 live state; any future drift
trips a typed error on cron.
