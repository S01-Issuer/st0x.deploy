# V4 upgrade runbook

End-to-end operational sequence for landing the V4 authoriser + corp-actions
upgrade. Each numbered step is a single discrete operator action — a workflow
dispatch, a PR merge, an on-device hardware signature, etc.

For the underlying mechanics (invariant libs, script-authoring lifecycle,
generic post-run process, naming + status conventions, forcing-function
pattern), see [`OPERATIONAL_SCRIPTS.md`](OPERATIONAL_SCRIPTS.md). This file is
the V4-specific runbook only.

---

## Prerequisites

- GitHub access with `workflow_dispatch` permission on the repo.
- Hardware wallet provisioned with one of the 6 ST0x token-owner Safe signer
  keys (need 3 signers per Safe-routed bundle).
- The `rainlang.eth` wallet, used once in Phase 1 only.

---

## Phase 0 — Land the lower V4 stack

Merge in stack order:
[#199](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/199) →
[#201](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/201) →
[#196](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/196) →
[#202](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/202) →
[#208](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/208) →
[#209](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/209).

After this main contains the refactored invariant libs, the V4 deploy pointer
hydration, and `run-script.yaml` with the V4 authoriser-clone script registered.

[#211](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/211),
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197),
[#198](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/198) stay open
with forcing-function reds until later phases hydrate them.
[#210](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/210) (this docs
PR) can merge anytime — it's independent of the stack.

---

## Phase 1 — Migrate beacon ownership to the Safe

`script/MigrateBeaconOwners.s.sol` transfers ownership of the three production
beacons from `rainlang.eth` to `STOX_TOKEN_OWNER_SAFE`. It's a direct EOA
broadcast (single signer, not a Safe bundle), so it runs **locally** with the
rainlang.eth wallet — not via a dispatched workflow.

1. Pull main locally.
2. Connect the rainlang.eth wallet via Frame (or use `--ledger`).
3. Run:
   ```shell
   BASE_RPC_URL=https://base-rpc.publicnode.com \
     forge script script/MigrateBeaconOwners.s.sol --rpc-url base --broadcast --slow
   ```
4. The script broadcasts 3 `transferOwnership(Safe)` calls (receipt beacon,
   receipt-vault beacon, wrapped-token-vault beacon) and re-asserts each
   beacon's `owner() == Safe` post-broadcast.
5. Verify on Basescan: each beacon's `owner` is now `0xe70d821f…`.

---

## Phase 2 — Deploy the 10 V4 impls

GitHub UI → **Actions** → **Manual sol artifacts** → **Run workflow**. Dispatch
each suite in order, waiting for each run to complete before starting the next:

1. `stox-receipt-v4`
2. `stox-receipt-vault-v4`
3. `stox-wrapped-token-vault-v4`
4. `stox-wrapped-token-vault-beacon-v4`
5. `stox-wrapped-token-vault-beacon-set-deployer-v4`
6. `stox-offchain-asset-receipt-vault-beacon-set-deployer-v4`
7. `stox-unified-deployer-v4`
8. `stox-offchain-asset-receipt-vault-authorizer-v1-v4`
9. `stox-offchain-asset-receipt-vault-payment-mint-authorizer-v1-v4`
10. `stox-corporate-actions-facet-v4`

Each dispatches `Deploy.sol` via the Zoltu deterministic deployer (CI-controlled
key from secrets), broadcasts to Base, verifies on Basescan, asserts the
freshly-deployed bytecode matches the codehash pinned in `LibProdDeployV4`. ~5
min per run. Order matters — each suite's deploy checks earlier-suite addresses
as deps.

---

## Phase 3 — Deploy the V4 authoriser clone (Bundle 1)

GitHub UI → **Actions** → **run-script** → **Run workflow**.

- `script`: `20260619-deploy-v4-authoriser-clone`
- `sig`: `run()`

Wait ~5 min for the run to complete. Then:

1. Open the run → **Summary** → download artifact
   `20260619-deploy-v4-authoriser-clone-run()-out`. Unzip → 1 JSON.
2. In the **Run script** step log, find and copy:
   - The `SafeTxHash: 0x…` line.
   - The `PredictedClone: 0x…` line.
3. Open the Safe UI on Base → switch to the ST0x token-owner Safe.
4. **Apps** → **Tx Builder** → drop the unzipped JSON.
5. Review the bundle (1 tx: `CloneFactory.clone(impl, initData)`).
6. **Send Batch** → the UI displays its canonical SafeTxHash. **Verify it
   matches step 2 byte-for-byte.** If not, abort and re-dispatch (nonce moved).
7. 3 signers each:
   - Open the queued tx in **Transactions**.
   - Click **Confirm**, approve on hardware device.
   - **Verify the on-device SafeTxHash matches step 2.**
8. Any signer clicks **Execute**.
9. From the executed receipt, capture the **clone address** from the
   `NewClone(sender, implementation, child)` event — the `child` field.
   Cross-check it matches `PredictedClone` from step 2.

---

## Phase 4 — Hydrate the clone pin ([#211](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/211))

1. Check out
   [#211](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/211)'s
   branch locally.
2. Edit `src/lib/LibProdDeployV4.sol`:
   - Replace `STOX_PROD_AUTHORISER_V4_CLONE = address(0)` with
     `address(<clone from Phase 3>)`.
   - Replace `STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH = bytes32(0)` with the
     EIP-1167 runtime codehash. Easiest:
     `cast keccak $(cast code <clone> --rpc-url base)`.
3. `git commit -am "feat(deploy): pin V4 authoriser clone address + codehash"`,
   push.
4. PR review — reviewer cross-checks the literal clone address against the
   `NewClone` event from Phase 3 + verifies the codehash via `cast keccak`
   against the live clone.
5. Merge [#211](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/211).

After merge:
[#209](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/209)'s
`mirrorGrants()` test passes;
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197)'s
`V4AuthoriserCloneNotPinned` forcing function clears.

---

## Phase 5 — Extend `expectedGrants()` to 13 (small follow-up PR)

The V4 override auto-grants 2 extra admin roles
(`SCHEDULE_CORPORATE_ACTION_ADMIN`, `CANCEL_CORPORATE_ACTION_ADMIN`) to the Safe
during `_initialize`. The invariant lib must enumerate them so post-V4 fork
tests assert the complete grant set.

1. Branch off main.
2. Edit `src/lib/LibAuthoriserInvariants.sol`:
   - Bump `new RoleGrant[](11)` → `new RoleGrant[](13)`.
   - Append:
     ```solidity
     grants[11] = RoleGrant(SCHEDULE_CORPORATE_ACTION_ADMIN, GRANTEE_TOKEN_OWNER_SAFE);
     grants[12] = RoleGrant(CANCEL_CORPORATE_ACTION_ADMIN, GRANTEE_TOKEN_OWNER_SAFE);
     ```
3. Commit, push, review, merge.

---

## Phase 6 — Mirror role grants onto the clone (Bundle 2)

GitHub UI → **Actions** → **run-script** → **Run workflow**.

- `script`: `20260619-deploy-v4-authoriser-clone`
- `sig`: `mirrorGrants()`

1. Download artifact `20260619-deploy-v4-authoriser-clone-mirrorGrants()-out`.
2. Capture `SafeTxHash` from the **Run script** log.
3. Safe UI → **Apps** → **Tx Builder** → drop JSON → **Send Batch**.
4. Cross-check SafeTxHash. 3 signers sign (verify on-device). Execute.

Bundle shape: 6 `grantRole(role, grantee)` calls on the clone. Clone now holds
all 13 grants (7 auto-granted in Phase 3 + 6 mirrored here).
[#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197)'s
`ExpectedGrantMissing` forcing function clears.

---

## Phase 7 — Execute the V4 upgrade ([#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197))

1. Merge [#197](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/197)
   (forcing function cleared in Phases 4 + 6; tests now pass).
2. GitHub UI → **Actions** → **run-script** → **Run workflow**.
   - `script`: `20260623-upgrade-receipt-vaults-to-v4`
   - `sig`: `run()`
3. Download artifact `20260623-upgrade-receipt-vaults-to-v4-run()-out`.
4. Capture `SafeTxHash`. Safe UI → **Tx Builder** → cross-check → 3 signers sign
   → Execute.

Bundle shape: 1 `upgradeTo(V4 impl)` on the receipt-vault beacon + N
`setAuthorizer(<clone>)` calls (one per production receipt vault). After
execution, every vault routes corp-action selectors via fallback delegatecall
and is gated by the V4 clone.

---

## Phase 8 — Post-execution pin ([#198](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/198))

1. Check out
   [#198](https://app.graphite.com/github/pr/S01-Issuer/st0x.deploy/198)'s
   branch.
2. Edit `src/lib/LibAuthoriserInvariants.sol`:
   ```diff
   -    address internal constant STOX_PROD_AUTHORISER = 0x35f9fA9d80aAF2B0fB27f0FF015641B3408d7456;
   +    address internal constant STOX_PROD_AUTHORISER = address(<clone from Phase 3>);
   ```
3. Update each impacted script's NatSpec status banner from `**PENDING.**` to
   `**EXECUTED YYYY-MM-DD.** SafeTxHash 0x… at nonce N`.
4. Commit, push, review (cross-check every literal against on-chain), merge.

V4 upgrade workstream complete. From this PR onward, every script's
`assertAll(safe)` pre-flight on main validates against the new V4 live state;
any future drift trips a typed error.
