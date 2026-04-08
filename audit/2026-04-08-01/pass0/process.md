# Pass 0 — Process Review

Documents reviewed:
- `CLAUDE.md` (118 lines) — primary process document
- `README.md` (27 lines) — repo overview
- `CHANGELOG.md` — version history (not process)

No nested `CLAUDE.md` / `AGENTS.md` files in tree.

Prior run `audit/2026-04-07-01/pass0/process.md` raised P0-1 (missing corp-actions arch), P0-2 (version bump criterion), P0-3 (underscore helper ambiguity), P0-4 (README stale), P0-5 (no `audit/`+`.fixes` workflow mention). P0-1, P0-2, P0-3 are now addressed in the current CLAUDE.md (lines 47–58, 95, 110–113). P0-4 and P0-5 still stand and are re-flagged below.

## Findings

### P0-1 — README.md Architecture list still stale

**Severity:** INFO

**Location:** `README.md` lines 19–26

`src/concrete/` is still described as "StoxReceipt, StoxReceiptVault, StoxWrappedTokenVault". It is missing:
- `StoxWrappedTokenVaultBeacon.sol`
- `StoxCorporateActionsFacet.sol`
- `src/concrete/authorize/` (authorizer subfolder introduced by the Stox authorizer PR)
- `src/interface/ICorporateActionsV1.sol`

`src/lib/` is described as "Production deployment addresses and codehashes" — but `src/lib/` now contains `LibCorporateAction`, `LibCorporateActionNode`, `LibStockSplit`, `LibRebase`, `LibTotalSupply`, `LibERC20Storage` in addition to `LibProdDeployV1/V2`.

README is public-facing and not loaded as Claude session context, so this is INFO — it won't trip sessions (CLAUDE.md is load-bearing for that), but it misleads human contributors reading the top-level doc. This is cosmetic enough that fixing it is optional.

**Originating PR:** #18 (adds the facet/interface/libs to `src/` surface).

### P0-2 — CLAUDE.md does not document the `audit/` + `.fixes/` workflow

**Severity:** INFO

**Location:** `CLAUDE.md` (no section currently describes the audit workflow)

`audit/<YYYY-MM-DD>-NN/` contains multiple prior runs (`2026-03-17-01`, `2026-03-18-01`, `2026-03-19-01`, `2026-04-07-01`) and `.gitignore` lists `.fixes`. Neither is mentioned in CLAUDE.md. A new Claude Code session running the audit skill discovers the directory convention and the `.fixes/` gitignore rule by accident. Under context compression, a session could easily re-create `audit/<date>-01/` with a different schema (e.g., forget to bump `NN`) or write proposed fixes to a committed path.

**Suggested addition** (1–2 lines, under a new "Audit Workflow" sub-heading or appended to the top-level conventions section):

> Audits live under `audit/<YYYY-MM-DD>-NN/pass<M>/`, one directory per audit run, `NN` bumped per run. Findings are written to per-file markdown files; proposed fixes for each LOW+ finding go in `.fixes/<FindingID>.md` (gitignored).

**Originating PR:** N/A (pre-existing repo convention not captured in CLAUDE.md). This is a documentation touch that can go on the stack base (#18) so it ships alongside the corporate-actions work, or on main directly.

### P0-3 — `known-false-positives.md` referenced by the audit skill does not exist

**Severity:** LOW

**Location:** `audit/` (file not present); referenced by `~/.claude/skills/audit/GENERAL_RULES.md` line 36

`GENERAL_RULES.md` instructs: "Before reporting findings, read `audit/known-false-positives.md` and do not re-flag any issue documented there." This file does not exist in the repo. Consequences:

- Every pass 0–5 agent will attempt to read it and get "file not found", then either silently proceed (today's behavior) or, under a stricter harness, fail-open and re-flag issues that earlier triage already dismissed as false positives.
- The 2026-04-07-01 triage dismissed several findings as "won't fix" or false positive — those dismissals are not captured anywhere a future audit will see them, so the same findings will resurface run after run.

Evidence that this is load-bearing: the 2026-04-07-01 pass5 findings include items like A05-P5-7 and A09-P5-3 that earlier runs had already debated. Without `known-false-positives.md` future runs relitigate them.

**Proposed fix:** Create `audit/known-false-positives.md` as an empty-but-present file with a short header explaining its purpose; future triage runs append to it when dismissing findings as false positives. Not in scope for this audit's fix phase unless I find FP-worthy dismissals during triage. Fix file: `.fixes/P0-3.md`.

**Originating PR:** N/A — repo/process convention fix. Lands on the stack base branch (#18) or on `main` as a preparatory touch.

## Items deliberately not flagged

- `CLAUDE.md` lines 47–58 (corporate-actions architecture) — accurate, explicit about the delegatecall boundary and storage-bearing libraries. Good. Resolves prior-run P0-1.
- `CLAUDE.md` line 95 (version bump criterion) — now has an explicit rule ("Bump ... only when a deployed contract's address or codehash changes"). Resolves prior-run P0-2.
- `CLAUDE.md` lines 110–113 (Naming Conventions) — explicit carve-out for inherited overrides and production-code `_internalName` convention. Resolves prior-run P0-3.
- `CLAUDE.md` line 55 and line 68 — load-bearing rules about `LibERC20Storage` OZ coupling and not removing unreferenced `LibProdDeploy*` constants. Both explicit and verifiable.
