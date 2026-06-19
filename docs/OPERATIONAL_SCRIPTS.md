# Operational scripts

This document is the how-to for everything under `script/` that authors a Safe
Tx Builder bundle (or any on-chain action) for the ST0x token-owner Safe to
sign. It covers the invariant libraries that scripts pre-flight against, the
lifecycle of writing + testing + dispatching a new script, and the
post-execution process for getting a bundle from a workflow artifact onto Base.

If you only need the canonical answer to "how do I add another one?", jump to
[§ Adding a new script](#adding-a-new-script).

> **Naming convention reminder**: every operational script lives flat in
> `script/` and is named `YYYYMMDD-<kebab-name>.s.sol`, where the date is when
> the script is added to the `run-script.yaml` dropdown. See [§ Naming](#naming)
> for the full rationale.

---

## Why invariants

Every state change the ST0x token-owner Safe authors is preceded by an
exhaustive on-chain pre-flight that asserts a bundle of properties. The script
and the Safe Tx Builder bundle the script emits both **trust those properties to
hold** — if the live chain disagrees with the lib's pinned expectation, the
script reverts before broadcasting, and signers never see a bundle that targets
the wrong state.

The pre-flight bundle is shared across every script via the `LibInvariants`
orchestrator and the four domain libs underneath it. New scripts pre-flight via
`LibInvariants.assertAll(safe)`; they don't re-derive invariants. New invariants
get added to a domain lib and become available to every existing script
automatically.

---

## Invariant library structure

The four domain libs each return silently when the pinned expectation holds and
revert with a **typed error** that pinpoints the drift otherwise. The typed
errors carry the expected + actual values so a debugger can see exactly which
value moved without re-running the script.

### `LibSafeInvariants` — Safe v1.4.1 invariants

Asserts properties of the production Safe at `STOX_TOKEN_OWNER_SAFE`:

- Proxy runtime codehash matches the pinned v1.4.1 L2 proxy codehash.
- Singleton (slot 0) matches the pinned v1.4.1 singleton address.
- Singleton's runtime bytecode codehash matches the pinned v1.4.1 singleton
  codehash (defends against `SELFDESTRUCT`-and-recreate).
- `VERSION()` returns `"1.4.1"`.
- Module list is empty (`SafeUnexpectedModules` otherwise).
- Guard slot is `address(0)` (`SafeUnexpectedGuard` otherwise).
- Fallback handler points at the pinned `CompatibilityFallbackHandler`.
- `getOwners()` returns the pinned owner set in linked-list order (newest-added
  at index 0).
- `getThreshold()` matches the pinned threshold.

The current-truth pins (owner set + threshold) update via PR when the Safe state
changes on-chain; the pin update lands in the same PR that records the
post-execution state. See the post-execution pin PR pattern at
[§ Post-execution pin](#post-execution-pin).

### `LibTokenInvariants` — vault ownership invariants

Asserts that every production receipt vault returned by
`LibTokenOwnership.productionReceiptVaults()` (currently 13 vaults) has its
`owner()` set to `STOX_TOKEN_OWNER_SAFE`. A vault whose owner diverges trips
`ReceiptVaultOwnerMismatch` with the vault address + expected vs actual owner —
a strong signal that a vault has been detached from the Safe between authoring
and execution.

### `LibBeaconInvariants` — beacon ownership + impl invariants

Asserts properties of the production `UpgradeableBeacon`s:

- Beacon has runtime code (`BeaconNotDeployed` otherwise).
- Beacon's runtime codehash matches the pinned OZ `UpgradeableBeacon` codehash.
- Beacon's `owner()` matches the expected owner (the EOA pre-migration, the Safe
  post-migration — the caller supplies which one).
- Beacon's `implementation()` matches the expected impl.

Used by `MigrateBeaconOwners` (pre + post ownership swap) and by the V4 upgrade
script (asserts the impl hasn't moved before broadcasting the `setAuthorizer`
bundle).

### `LibAuthoriserInvariants` — authoriser role grants

Asserts properties of the live authoriser clone at `STOX_PROD_AUTHORISER`:

- Codehash matches the EIP-1167 minimal-proxy runtime computed from the pinned
  authoriser impl address (`CloneCodehashMismatch` otherwise — the clone has
  been etched over or doesn't point at the expected impl).
- For every `(role, grantee)` pair in `expectedGrants()`, the clone's
  `hasRole(role, grantee)` returns `true` (`ExpectedGrantMissing` otherwise).
- `DEFAULT_ADMIN_ROLE` (`bytes32(0)`) is held by nobody — the contract uses
  per-role `_ADMIN` self-admin pattern instead.

### `LibInvariants` — orchestrator

`LibInvariants.assertAll(safe)` bundles the Safe-side
(`LibSafeInvariants.assertAll(safe)`) and token-side
(`LibTokenInvariants.assertAll()`) invariants in one call. Scripts that only
need Safe checks call `LibSafeInvariants.assertAll(safe)` directly; scripts that
touch token state (vault upgrades, owner migrations) use the orchestrator.

---

## Two overloads on every `assertAll`

Every `assertAll` family function (on every domain lib) ships in **two shapes**:

```solidity
// (a) No-arg overload — fills in every expected value from the lib's
// pinned current-truth constants. This is the canonical pre-flight: it
// asserts the live chain still matches what the lib says is true.
function assertAll(IGnosisSafe safe) internal view;

// (b) Full-args overload — caller supplies every expected value
// explicitly. This is the canonical post-state assertion: it asserts a
// deliberately-changed value (e.g. the new threshold post-bundle) while
// every other value still matches the pinned current-truth defaults.
function assertAll(
    IGnosisSafe safe,
    uint256 expectedThreshold,
    address[] memory expectedOwnerSet
) internal view;
```

### How the overloads are used together

Every script follows the same shape:

```solidity
function run() external {
    IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

    // (1) Pre-flight against current-truth pins.
    LibInvariants.assertAll(safe);

    // (2) Build the inner-tx data.
    SafeTx memory txn = SafeTx({
        to: address(safe),
        value: 0,
        data: abi.encodeCall(IGnosisSafe.changeThreshold, (TARGET_THRESHOLD)),
        operation: 0
    });

    // (3) Compute the canonical SafeTxHash at the pre-execution nonce.
    uint256 nonce = safe.nonce();
    bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txn, nonce);

    // (4) Simulate the inner call locally.
    LibSafeOps.simulateSelfCall(safe, txn.data);

    // (5) Post-state assertion — use the full-args overload to override
    //     ONLY the value the bundle deliberately changes; everything else
    //     still asserts against the pinned current truth.
    LibSafeInvariants.assertAll(safe, TARGET_THRESHOLD, LibSafeInvariants.expectedOwners());

    // (6) Emit the Tx Builder JSON + log the canonical SafeTxHash.
    SafeTx[] memory txs = new SafeTx[](1);
    txs[0] = txn;
    string memory json = LibSafeOps.emitTxBuilderJson(
        address(safe), block.chainid, BUNDLE_NAME, txs
    );
    vm.writeFile(ARTIFACT_PATH, json);

    console2.log("==== TX BUILDER JSON BEGIN ====");
    console2.log(json);
    console2.log("==== TX BUILDER JSON END ====");
    console2.log("SafeTxHash:", vm.toString(safeTxHash));
    console2.log("Nonce:", nonce);
}
```

The pattern guarantees: **the bundle the signer sees would produce a Safe state
that still passes every invariant except the one the bundle deliberately
changes**. If anything else moves (a new module shows up between authoring and
execution, a vault loses ownership, etc.) the post-state assertion trips before
the JSON is even written.

---

## Adding a new script

### 1. Branch off main

```shell
gt checkout main && git pull
gt create -m "feat(deploy): YYYYMMDD <description>"
```

### 2. Create the script file

`script/YYYYMMDD-<kebab-name>.s.sol`, where the date is **today** (the day
you're adding the script to the dropdown). The script declares one top-level
`contract`. File-level NatSpec leads with a `**PENDING.**` status banner:

```solidity
/// @title <ContractName>
/// @notice **PENDING.** <one-liner explaining what state the bundle changes>.
/// @dev Two entrypoints:
/// - `run()`: dry-run + emit Safe Tx Builder JSON + log canonical SafeTxHash.
/// - `verify(string jsonPath)`: re-run pre-flight + assert an existing artifact
///   matches what the live pre-flight would emit.
```

### 3. Implement `run()`

Follow the shape above. Specifically:

1. **Pre-flight.** Call the broadest no-arg `assertAll` that covers the state
   the bundle touches. For Safe-only state changes use
   `LibSafeInvariants.assertAll(safe)`. For state changes that also depend on
   the receipt vaults (e.g. confirming uniform ownership) use
   `LibInvariants.assertAll(safe)`. Authoriser-touching scripts add
   `LibAuthoriserInvariants.assertAll(IAccessControl(authoriser))`.

2. **Build the inner-tx data.** Encode the inner call via
   `abi.encodeCall(IInterface.fn, args)` — avoid raw `abi.encodeWithSignature`
   so the type system catches signature drift.

3. **Compute the canonical SafeTxHash.**
   `LibSafeOps.computeSafeTxHashViaSafe(safe, txn, safe.nonce())`. The hash is
   what signers see in the Safe UI.

4. **Simulate the inner call.** `LibSafeOps.simulateSelfCall(safe, txn.data)`
   `vm.prank(safe)`s the Safe and calls into itself, mutating the fork's state
   to the post-execution Safe state. This is what makes the post-state assertion
   meaningful.

5. **Re-assert post-state.** Use the full-args `assertAll` overload. Override
   only the value the bundle deliberately changes; pull every other expected
   value from the lib's pinned current-truth.

6. **Emit Tx Builder JSON.**
   `LibSafeOps.emitTxBuilderJson(safeAddr, chainId, bundleName, txs)`. Write the
   JSON to `out/<descriptive-name>.json` with `vm.writeFile`. The path goes into
   `foundry.toml`'s `fs_permissions` list if it isn't already covered.

7. **Log the SafeTxHash + nonce** between explicit
   `==== TX BUILDER JSON BEGIN ====` / `==== TX BUILDER JSON END ====` markers
   so CI logs are greppable.

8. **n+1 reversibility check** (where applicable). For threshold / ownership /
   authoriser changes, prove the new state is not a dead end by simulating the
   inverse tx and asserting it succeeds. See `LibSafeOps.simulateNPlus1Reversal`
   for the canonical helper.

### 4. Implement `verify(string memory jsonPath)`

Mirrors `run()`'s pre-flight, parses the existing JSON via
`LibSafeOps.parseTxBuilderJson(jsonPath)`, asserts every field matches what the
live pre-flight would emit. Used by signers and auditors to re-derive the bundle
hash post-execution. Typed `VerifyMismatch(string field)` on first divergence.

### 5. Write tests

`test/script/YYYYMMDD-<kebab-name>.t.sol` — same file naming convention. Use
`vm.createSelectFork(LibRainDeploy.BASE)` against an unpinned head fork (live
drift detector). Required test cases:

- **`testRunCompletesAndWritesArtifact`** — happy path. Asserts the artifact is
  written, has the expected `meta.name`, and exactly the expected number of txs.

- **`testVerifyAcceptsRunArtifact`** — round-trip property. `run()` emits →
  `revertToState` snapshot back to pre-run → `verify()` against the artifact
  succeeds silently.

- **Inverted: every invariant the script asserts.** For each typed error the
  pre-flight can raise (Safe codehash, owner set, threshold, vault ownership,
  etc.), write an inverted test that mocks the live state to trip that specific
  error. Pattern:

  ```solidity
  function testRunRejectsThresholdDrift() external {
      selectBaseFork();
      vm.mockCall(address(safe), abi.encodeWithSelector(IGnosisSafe.getThreshold.selector), abi.encode(uint256(7)));
      vm.expectRevert(abi.encodeWithSelector(
          SafeThresholdMismatch.selector, address(safe), uint256(1), uint256(7)
      ));
      script.run();
  }
  ```

- **Inverted: `verify` rejects forged artifacts.** For each field the artifact
  pins (chainId, safeAddress, tx data, tx count), write an inverted test that
  forges a JSON with that field perturbed and asserts the matching
  `VerifyMismatch` typed error.

The test suite is the script's safety net: if a new invariant lands in a domain
lib later, the script picks it up automatically (because it calls the
orchestrator), and the new inverted test in the lib's test suite covers it.
Don't duplicate domain-lib tests in the script's test suite — only test the
script's own bundle-emitting + assertion logic.

### 6. Register the script in the workflow dropdown

Edit `.github/workflows/run-script.yaml`. Append your script's date-prefixed
name (without extension) to the `inputs.script.options` list, **at the bottom**:

```yaml
options:
  # Append-only registry. Re-dispatching a historical script must remain
  # possible — never reorder or delete entries.
  - 20260619-migrate-multisig-threshold
  - 20260619-deploy-v4-authoriser-clone
  - 20260720-rotate-corp-action-grantees # <-- new entry here
```

The dropdown is **append-only**. Re-running a historical script (e.g. to
retrospectively re-derive its bundle for audit) must remain possible, so entries
are never reordered or deleted even after the script has executed.

### 7. Open the PR

Open the PR like any other change. CI runs `forge build`, `forge fmt
--check`,
`slither`, `rainix-sol-single-contract`, the full test suite (including your
inverted tests), and a separate **`build-artifact` workflow** that dispatches
your script's `run()` against the Base head fork and uploads `out/*.json` so
reviewers can download the bundle directly from the run.

If your script's pre-flight depends on a state that hasn't happened yet (e.g. a
clone address that will only be hydrated post-deployment), the forcing-function
pattern is deliberate — the test trips a typed error and stays red on CI until
the upstream literal is filled in. Mention this explicitly in the PR description
so reviewers know the red CI is load-bearing.

---

## Naming

- **File**: `script/YYYYMMDD-<kebab-name>.s.sol`. The date is the day the script
  is added to the dropdown. Chronological order drops out from `ls script/`.
- **Test file**: `test/script/YYYYMMDD-<kebab-name>.t.sol`. Mirrors the script.
- **Contract**: `contract <PascalName>` inside the script. The contract name is
  NOT date-prefixed — the file name carries the date.
- **Bundle name** (`meta.name` in the Tx Builder JSON): a human-readable string
  visible to signers in the Safe UI. Convention: `"ST0x <subsystem> - <action>"`
  (e.g. `"ST0x Safe threshold 1->3 (post-rotation roster)"`,
  `"ST0x V4 authoriser - deploy clone"`).
- **Artifact path**: `out/<descriptive-name>.json`. Listed in `foundry.toml`
  `fs_permissions` (the `out/` entry is repo-wide read-write, so no per-script
  changes needed).

---

## Status lifecycle in NatSpec

The script's file-level NatSpec leads with a status banner that reflects whether
the bundle has been executed:

```solidity
// Before execution:
/// @notice **PENDING.** <…>

// After execution:
/// @notice **EXECUTED YYYY-MM-DD.** The bundle was signed by the
/// post-rotation roster and landed on Base at nonce N with `SafeTxHash`
/// `0x…`. Retained verbatim for retrospective re-verification.
```

The status banner update lands in the post-execution pin PR (see below). The
script itself is not moved — it stays at its original path forever.

---

## Post-execution pin

After the bundle has executed on-chain, a follow-up PR records the new canonical
state in the relevant invariant lib's constants. For the threshold migration
this means bumping `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD` from `1`
to `3`; for a roster swap it means updating the owner address constants. The
post-execution pin PR is typically a one-line lib change plus the NatSpec status
banner update on the script itself.

The pattern: **the lib's pinned constants are the source-of-truth for the live
chain state at the point a script runs**. If a script deliberately changes that
state, the script's pre-flight pins the pre-execution state, and a follow-up pin
PR records the post-execution state. From that PR onward, every other script's
pre-flight uses the new pin and would trip if the chain drifted away from it.

### Merging the invariant with the script — the migration-window pattern

For a value the script deliberately mutates from `pre` to `post`, the post-
execution pin above lands in a **separate** PR after the script has actually run
on-chain. That leaves a window in which live-chain drift on that value would go
undetected by cron — no invariant is watching it, because no invariant can pin
both states at once.

`LibMigrationInvariant` closes that window. It asserts a live value matches
either `pre` OR `post` up until an operator-SLA `deadline`, then enforces `post`
only:

```solidity
LibMigrationInvariant.assertMigration(
    "STOX_RECEIPT_VAULT_BEACON_V1.owner()",   // label (surfaced in revert data)
    Ownable(beacon).owner(),                   // live-chain read
    LibProdDeployV1.BEACON_INITIAL_OWNER,      // pre  — script has not run yet
    LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,   // post — script has run
    1_788_220_800                              // deadline — unix ts, 2026-09-01 UTC
);
```

- **Before `deadline`**: `actual == pre` OR `actual == post` passes; any other
  value trips `MigrationStateDrift`. Both sides of the transition are covered by
  cron, so drift into a third value surfaces immediately.
- **At/after `deadline`**: only `actual == post` passes; anything else trips
  `MigrationDeadlinePassed`. If the script has not landed on-chain by then, cron
  red-lines and forces the operator to make an explicit choice: **run the
  script**, **extend the deadline**, or **delete the invariant** (accepting
  `pre` as the new canonical if the migration is being abandoned).

This lets the invariant test PR merge **alongside** the script PR — the
migration itself is covered by cron enforcement even while pending, rather than
being invisible to CI until the follow-up pin PR lands. It also gives the
operational SLA teeth: a script left un-run isn't just a stale PR, it's a red
cron.

Overloads on `assertMigration` cover `bytes32`, `address`, and `uint256`
directly so the caller does not have to hand-cast.

The `label` string is echoed verbatim in every revert. Pick something that
identifies the exact slot being asserted — a good format is
`"<ContractOrConstant>.<selector>()"` (e.g.
`"STOX_RECEIPT_VAULT_BEACON_V1.owner()"`) so a failing check tells you both what
value drifted and which one it was.

**Picking the deadline.** Rule of thumb: the operator SLA on running the script,
floored by a comfortable buffer for review + scheduling — for the beacon-owner
migration a 6-8 week window from PR merge is typical. Store the deadline as a
`uint256 constant` in the test file that consumes it, not in a central registry
— the deadline is a property of that specific invariant, not of the migration
script, and lives closest to the assertion that reads it.

**Removing the invariant after the migration lands.** Once the script has
executed on-chain and the follow-up pin PR has bumped the lib constant to
`post`, the dual-state block becomes redundant — the pin now guards `post`
directly. Two clean options:

1. **Collapse into the standard pin.** Delete the `assertMigration` call; the
   lib constant + whatever `assertBeaconInvariants` / `assertAll` bundle already
   covers that slot enforces `post` from then on.
2. **Leave it as `pre == post`.** If you want the file to keep documenting the
   migration history, replace `pre` with `post` — the check becomes a plain
   equality and the deadline branch is dead code, but the file still records
   what changed.

Prefer option 1 unless the historical note is genuinely useful; less code is
better than defensive residue.

---

## Operator runbook: dispatch → sign → execute → pin

This is the canonical step-by-step from the operator's perspective. Everything
from clicking "Run workflow" through the post-execution lib pin.

### 1. Dispatch the workflow

GitHub UI → **Actions** tab → **run-script** workflow (left sidebar) → **Run
workflow** button (top right of the workflow runs list).

The dispatch form has two inputs:

- **`script`** — dropdown of every registered operational script. Pick the
  date-prefixed name of the script you want to dispatch (e.g.
  `20260619-deploy-v4-authoriser-clone`).
- **`sig`** — dropdown of the entrypoint to call. Defaults to `run()`. Some
  scripts ship multiple entrypoints (e.g. the V4 authoriser deploy has `run()`
  for the clone-deploy bundle and `mirrorGrants()` for the grants bundle); pick
  the one you want.

Click **Run workflow**. The runner takes ~5 min: nix install, soldeer install,
`forge script script/<name>.s.sol --sig '<sig>' --rpc-url base
--no-storage-caching`,
upload artifact.

### 2. Download the Tx Builder JSON artifact

Once the workflow turns green, open the run → **Summary** tab → scroll to the
**Artifacts** section at the bottom → download `<script>-<sig>-out.zip` (e.g.
`20260619-deploy-v4-authoriser-clone-run()-out.zip`).

Unzip → you have a single `.json` file (the Safe Tx Builder bundle).

### 3. Capture the canonical SafeTxHash from the workflow log

In the same workflow run, open the **Jobs** tab → **run** job → **Run script**
step. Scroll to find the block:

```
==== TX BUILDER JSON BEGIN ====
{"version":"1.0","chainId":"8453",…}
==== TX BUILDER JSON END ====
SafeTxHash: 0x…
Nonce: …
```

Copy the `SafeTxHash` value to a scratch note — you'll cross-check it in the
Safe UI in the next step. If the script also prints a `PredictedClone:
0x…` line
(or any other script-specific predicted value), copy that too.

### 4. Upload the JSON to Safe Tx Builder

Open the [Safe UI](https://app.safe.global) → switch to the ST0x token-owner
Safe (Base chain) → left sidebar **Apps** → **Tx Builder** (by Safe). Drop the
downloaded JSON into the upload zone.

The UI parses the bundle and displays each tx in the batch (target address,
value, calldata, decoded function call). Eyeball-verify the displayed targets
match your expectations.

### 5. Verify the SafeTxHash matches — abort if it doesn't

Click **Send Batch** → the UI displays the canonical `SafeTxHash` it would sign
at the **current Safe nonce**. **Cross-check this against the value from step 3
byte-for-byte.**

If the values match: continue.

If they don't: another Safe tx must have executed between authoring and this
dispatch, advancing the nonce. **Stop, abort the Safe UI flow.** Re-dispatch the
workflow (step 1) to refresh the artifact at the new nonce, and start over from
step 2. Do **not** sign anything until the hashes match.

### 6. Three signers sign (3-of-6)

Each signer (3 of the 6) does the following independently:

1. Open the Safe UI, switch to the ST0x Safe.
2. **Transactions** tab → **Queued** sub-tab → find the queued tx (it appears
   here after the first signer initiates Send Batch in step 5).
3. Click the tx → review the calldata + SafeTxHash shown on screen.
4. Connect their hardware wallet → click **Confirm**.
5. The hardware wallet displays the calldata + the canonical SafeTxHash on its
   own screen. **Verify the on-device SafeTxHash matches the workflow log value
   from step 3.** The on-device hash is the authoritative artifact the key
   signs; the Safe UI is helpful but not security-load-bearing.
6. Approve on-device.

Repeat across three signers. The Safe UI's tx page shows a running count of
collected signatures.

### 7. Execute

Once 3 signatures are collected, the **Execute** button activates in the Safe
UI. Any signer (or any EOA — the gas payer doesn't need to be a signer) clicks
**Execute** and broadcasts the tx. Watch for the **Successful** state and
capture the on-chain tx hash.

### 8. Capture the on-chain artifacts

From the executed tx's receipt (Basescan or your wallet's tx detail):

- The **on-chain SafeTxHash** (emitted in the Safe's `ExecutionSuccess` event).
  Used to retroactively prove which bundle landed.
- Any **deployed contract addresses** the bundle produced. For EIP-1167
  `CloneFactory.clone(impl, initData)` bundles, read the
  `NewClone(sender, implementation, child)` event — `child` is the new clone
  address. For Zoltu deploys, the address is in the `ContractCreation` event.
- The new **on-chain nonce** of the Safe (for cross-reference if you'll
  immediately author another bundle).

### 9. Open the post-execution pin PR (the lib hydration)

The post-execution pin PR is the **last** step in every script's workstream. It
converts the just-landed on-chain state into a new lib-pinned current-truth that
every subsequent script's `assertAll` pre-flight will validate against.

What to update:

1. **The script's NatSpec status banner.** Replace `**PENDING.**` with
   `**EXECUTED YYYY-MM-DD.** SafeTxHash 0x… at nonce N. Retained verbatim
   for retrospective re-verification.`
2. **The invariant lib's current-truth constant(s).** Depending on what the
   bundle changed, edit one of:
   - `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD` (threshold migration) —
     change the literal from the old value to the new.
   - `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_N` (roster swap) — update
     each owner address constant.
   - `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE` (clone deploy) — replace
     `address(0)` with the literal clone address from step 8, and replace
     `STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` with the EIP-1167 runtime codehash
     computed via
     `keccak256(abi.encodePacked(hex"363d3d373d3d3d363d73", v4Impl,
     hex"5af43d82803e903d91602b57fd5bf3"))`.
   - `LibAuthoriserInvariants.STOX_PROD_AUTHORISER` (authoriser swap) — point to
     the new clone.
3. **Push to the pin PR's branch.** CI runs — the script's tests now pass (the
   lib pin matches the new live state) and dependent PRs' forcing functions
   clear if applicable.
4. **Review the diff against on-chain.** Every literal that lands in the lib
   MUST match the value captured in step 8. Cross-check by hand or via
   `cast call` for an extra layer of safety.
5. **Merge.** From this PR onward, every other script's `assertAll` pre-flight
   uses the new pin; any future drift trips a typed error.

---

## V4 upgrade runbook

See [`V4_UPGRADE_RUNBOOK.md`](V4_UPGRADE_RUNBOOK.md) — the V4-specific operator
runbook lives in its own file. Eight phases, each with the exact workflow +
dropdown + signature + lib-edit steps to execute:

1. Land the lower V4 code stack.
2. Migrate beacon ownership to the Safe (rainlang.eth EOA broadcast).
3. Deploy the 10 V4 impls via `Manual sol artifacts`.
4. Deploy the V4 authoriser clone via `run-script` (`run()`).
5. Hydrate the clone pin in `LibProdDeployV4`.
6. Extend `LibAuthoriserInvariants.expectedGrants()` to 13.
7. Mirror role grants via `run-script` (`mirrorGrants()`).
8. Execute the V4 upgrade + post-execution pin.

Future workstreams (a new threshold migration, a fresh issuer rotation, an
authoriser re-clone) get their own `<TOPIC>_RUNBOOK.md` siblings; this main doc
stays scoped to the cross-cutting mechanics.

---

## Re-verification (auditors / signers later)

Any signer or auditor can re-derive any historical bundle's SafeTxHash by
re-running its script against current chain state:

```shell
BASE_RPC_URL=https://base-rpc.publicnode.com \
  forge script script/<YYYYMMDD-name>.s.sol \
  --rpc-url base \
  --sig 'verify(string)' \
  out/<descriptive-name>.json
```

A silent exit means the artifact matches what the current pre-flight would emit.
A typed `VerifyMismatch(string field)` revert pinpoints the first field that
drifted.

**Why this works after the bundle has executed**: the pre-flight in `verify()`
runs against current live state. If the lib's pinned constants reflect the
post-execution state (i.e. the post-execution pin PR has merged), then the
pre-flight passes, the parsed artifact's `SafeTxHash` still matches what the
live pre-flight would emit, and `verify()` succeeds. The historical bundle stays
re-verifiable as long as the libs and the script are preserved.

---

## Forcing-function pattern

Multiple scripts deliberately ship in a "PENDING" state where their pre-flight
reverts until a sibling state change happens. Examples:

- The V4 upgrade script (`UpgradeReceiptVaultsToV4.s.sol`) trips
  `V4ImplNotDeployed` until the V4 implementations are deployed via
  `manual-sol-artifacts.yaml`.
- The V4 authoriser-deploy script (`20260619-deploy-v4-authoriser-clone.s.sol`)
  trips `CloneFactoryNotDeployed` if the canonical CloneFactory at
  `0x444acC…dCb39` lacks code on the active fork (e.g. on a fresh testnet).
- The post-rotation threshold migration trips `SafeOwnerCountMismatch` until the
  manual roster swap has completed on Base.

The red CI on these PRs is the explicit forcing function: the bundle **cannot**
be signed until the upstream state has settled, and the script's own test suite
reminds reviewers of that fact every time CI runs. Don't paper over a red CI
with `vm.mockCall` shortcuts inside the script's tests — the red is
load-bearing.

---

## Tx Builder caveats

- **Bundles can't reference earlier txs' outputs.** A Safe Tx Builder bundle is
  a static array of `(to, value, data, operation)` quadruples; there's no
  facility to use the return value or emitted event of tx N in tx N+1. If a
  script's intent requires this (e.g. deploy a clone via `CloneFactory.clone()`
  then grant roles on the new clone), split into two bundles authored by two
  script entrypoints: one that deploys, one that takes the new address as an
  input parameter and emits the grants. See
  `20260619-deploy-v4-authoriser-clone.s.sol`'s `run()` +
  `mirrorGrants(address clone)` pattern.

- **The Safe nonce is captured at authoring time.** If another bundle executes
  between authoring and signing, the captured nonce is stale and the SafeTxHash
  will mismatch when signers verify in the UI. Re-run the workflow to surface
  the fresh hash.

- **`delegatecall` operations (operation = 1) require explicit signer
  awareness.** ST0x scripts default to `operation: 0` (standard call). Any
  script that needs `delegatecall` must clearly document why in the script
  NatSpec + PR description, and signers must double-check the target is one of
  the expected delegate targets (MultiSendCallOnly, etc.).

---

## When to write a script vs. a manual Safe UI tx

Use a script when:

- The action depends on invariants that the script can pre-flight against (any
  cross-cutting state — vault ownership, beacon impl, authoriser grants, etc.).
- The bundle has more than one inner tx and you want atomic authoring.
- The action will be re-derivable for audit later (most production state changes
  qualify).
- The action is non-trivial calldata that benefits from type-checked encoding
  (`abi.encodeCall(IInterface.fn, args)` over hand-encoded hex).

A manual Safe UI tx is fine when:

- The action is a single one-off with no invariant dependencies (e.g. adding a
  new signer to the Safe under a 1-of-N threshold).
- The calldata is trivially auditable by a signer reading the UI.
- No future audit / re-verification will need the bundle.

When in doubt, write a script. The cost is ~half a day of authoring and one PR
review; the benefit is the bundle stays auditable and re-verifiable forever.
