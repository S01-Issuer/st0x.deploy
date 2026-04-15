# Pass 0 — Process Review

Documents reviewed:
- `CLAUDE.md` (102 lines) — main process document for Claude Code sessions
- `README.md` (26 lines) — repo overview
- `CHANGELOG.md` (108 lines) — version history (project state, not process)

No other CLAUDE.md / AGENTS.md files exist in the tree.

## Findings

### P0-1 — CLAUDE.md Architecture section is missing the corporate actions / diamond facet stack

**Severity:** LOW

**Location:** `CLAUDE.md` lines 37–58 (Architecture section)

The Architecture section enumerates the beacon-proxy + ERC4626 vault pattern and lists `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxWrappedTokenVaultBeacon`, the beacon set deployers, and `StoxUnifiedDeployer`. It does **not** mention:

- `StoxCorporateActionsFacet` (the diamond facet entry point) — `src/concrete/StoxCorporateActionsFacet.sol`
- `ICorporateActionsV1` interface — `src/interface/ICorporateActionsV1.sol`
- The diamond facet pattern itself, what diamond it attaches to, and how facet storage isolation works
- Supporting libraries: `LibCorporateAction`, `LibCorporateActionNode`, `LibStockSplit`, `LibRebase`, `LibTotalSupply`, `LibERC20Storage`

The whole point of the corporate-actions stack (#16, #18, #21–25) is to introduce a new architectural surface: a diamond facet plus storage libraries that interact with totalSupply and rebases. A future Claude Code session reading CLAUDE.md to onboard will not know the diamond facet exists, will not know the rebase/totalSupply offset model, and will not know which libraries are storage-bearing vs pure helpers. That is exactly the kind of context that causes a future session to misinterpret instructions or duplicate work.

**Why this is a process finding (not a doc finding):** Pass 3 reviews NatSpec on individual source files. This is about the project-level onboarding doc that future agents read first.

### P0-2 — "Update CHANGELOG.md under the current version heading" leaves no rule for when to bump versions

**Severity:** LOW

**Location:** `CLAUDE.md` line 80 (Versioning section)

> "Update `CHANGELOG.md` with the change under the current version heading"

There is no defined criterion for when a change warrants a new version heading (V2 → V3) versus being appended under the existing version. This matters because:

- The corporate actions facet introduces new contracts with new addresses. Are those V2 additions or do they form V3?
- The CHANGELOG already groups "Zoltu deterministic deployment" under V2; is "Diamond facet" the same V2, or a new version?
- Future sessions adding contracts will silently extend whichever version they happen to read, producing inconsistent bumps.

This is fragile under context compression: if a session loses the rationale for the current version split, it has no rule to fall back on.

**Suggested rule** (for the user to ratify, not auto-applied): "Bump to a new version heading when any deployed contract address or codehash changes; otherwise append under the current version."

### P0-3 — "No meaningless `_`-prefixed helpers" is ambiguous about scope

**Severity:** LOW

**Location:** `CLAUDE.md` lines 96–98 (Naming Conventions section)

> **No meaningless `_`-prefixed helpers.** All function names must be descriptive and convey what the function does. This applies to all files including tests.

The literal text "no `_`-prefixed helpers ... applies to all files" reads as a blanket ban on leading-underscore function names. But:

- Solidity convention (and OpenZeppelin's codebase, which is inherited transitively here) uses `_internalFunction` to mark `internal`/`private` visibility. The repo's own dependencies use this convention everywhere.
- The qualifier "meaningless" is doing all the work and is undefined. A future session under context compression could either (a) read this as a literal ban and rename inherited `_msgSender` / `_update` overrides — breaking inheritance — or (b) ignore it entirely.

The prior triage entry `A05-P4-1` (FIXED) renamed `_`-prefixed helpers in **test files** specifically. That history clarifies the intent (test helpers shouldn't use `_foo` as a placeholder name) but the rule itself doesn't carry that context.

**Suggested rewording:** "Test helpers must have descriptive names, not `_foo` placeholders. Production code may use the `_internalName` convention to mark internal/private visibility, matching OpenZeppelin/Solidity convention."

### P0-4 — README.md Architecture list is stale

**Severity:** INFO

**Location:** `README.md` lines 19–26

README's `src/concrete/` description is "StoxReceipt, StoxReceiptVault, StoxWrappedTokenVault" — missing the beacon, the corporate actions facet, the authorizers, and the deploy subfolder. README also lists `src/lib/` as "Production deployment addresses and codehashes" — but `src/lib/` now also contains the corporate-action libraries, the rebase/totalSupply storage libraries, and `LibERC20Storage`. README is a public-facing doc and won't trip Claude sessions hard (CLAUDE.md is the load-bearing one), so this is INFO.

### P0-5 — CLAUDE.md does not document the `audit/` and `.fixes/` workflow

**Severity:** INFO

`audit/<date>-NN/` directories exist with prior triage history (2026-03-17/18/19) and `.fixes` is in `.gitignore`, but CLAUDE.md never tells a future session that the project follows the audit skill's pass-and-triage workflow. A new session running `/audit` discovers this by accident. Mentioning the workflow in CLAUDE.md (one line: "Audits live under `audit/<date>-NN/` and follow the audit skill's pass-and-triage workflow; proposed fixes are written to `.fixes/` and gitignored") would prevent confusion. INFO because it's missing context, not actively wrong.

## Items deliberately not flagged

- Build commands, fork test setup, dependency remappings, compiler settings — all clearly stated and unambiguous.
- "Address constants in `LibProdDeploy*` ... do not remove them even if they appear unreferenced" (line 55) — explicit, unambiguous, robust under compression. Good.
- "Source contracts should reference addresses through the versioned `LibProdDeploy*` libraries, not import bare constants directly from `src/generated/*.pointers.sol`" (line 57) — explicit and verifiable. Good.
- ICloneableV2 dual-initialize description (line 47) — explicit and accurate.
