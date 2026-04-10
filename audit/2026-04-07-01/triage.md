# Audit Triage — 2026-04-07-01

User pre-authorized triage and fixing without per-finding prompting.

## Carried forward from prior triages

Items DISMISSED in `audit/2026-03-19-01/triage.md` that remain DISMISSED:
- A03-1 (2026-03-19) — StoxReceipt behavioral tests, dependency boundary. **Note:** finding ID collision with the new A03-1 inflation bug below; the prior one carries through as `prev-A03-1` for clarity.
- A09-P3-2 / A07-P3-4 — Deployment event NatSpec wording. Dismissed.
- A10-P2-1 — V1 creation bytecode constants. Dismissed.

## Findings (LOW+) — current run

| ID | Pass | Severity | Title | Disposition | PR |
|---|---|---|---|---|---|
| P0-1 | 0 | LOW | CLAUDE.md missing diamond facet/corp-actions architecture | FIXED | PR1 |
| P0-2 | 0 | LOW | Versioning section lacks bump rule | FIXED | PR1 |
| P0-3 | 0 | LOW | "_-prefixed helpers" rule ambiguous about scope | FIXED | PR1 |
| P0-4 | 0 | INFO | README.md stale | DISMISSED — INFO, README isn't load-bearing | — |
| P0-5 | 0 | INFO | CLAUDE.md doesn't document audit/.fixes workflow | DISMISSED — INFO | — |
| **A03-1** | 1 | **CRITICAL** | **Mint/transfer to fresh account post-split inflates balance** | **FIXED — code + tests** | **PR4 (root) + PR5 (totalSupply test)** |
| **A26-1** | 1 | **CRITICAL** | **`migratedBalance` zero-balance early return is the root cause of A03-1** | **FIXED — code change** | **PR4** |
| A26-P2-1 | 2 | CRITICAL | `testZeroBalanceUnchanged` enshrines the bug | FIXED — test rewritten | PR4 |
| A03-P2-1 | 2 | HIGH | No integration tests for vault corp-actions hooks | FIXED — 8 tests added | PR4 + PR5 |
| A28-P2-1 | 2 | HIGH | No vault-level test for LibTotalSupply integration | FIXED via A03-P2-1 | PR4 + PR5 |
| A28-1 | 1 | HIGH | totalSupply ↔ balanceOf invariant violated by A03-1 | FIXED via A03-1 | (consequence) |
| A01-P5-1 | 5 | MEDIUM | Oracle traversal getters use ALL filter, return pending | FIXED — added CompletionFilter param to interface | PR6 |
| A23-1 | 1 | MEDIUM | LibERC20Storage layout-drift undetected | FIXED — added invariant test | PR4 |
| A27-1 | 1 | MEDIUM | LibStockSplit validateParameters allows near-zero multipliers | FIXED — added float magnitude bound | PR3 |
| A01-1 | 1 | LOW | `_authorize` passes empty data, losing per-action context | DEFERRED — design discussion needed; not fixed in this audit | — |
| A03-2 | 1 | INFO | Defensive cursor bounds check | DISMISSED — INFO | — |
| A21-1 | 1 | LOW | Unbounded `bytes parameters` on schedule | DEFERRED — authorizer is current safeguard | — |
| A23-2 | 1 | INFO | setBalance/setTotalSupply unprotected | DISMISSED — by design | — |
| A26-P2-2 | 2 | LOW | No test for non-split nodes interspersed | DEFERRED — speculative until other action types exist | — |
| A26-2 | 1 | INFO | int256(balance) cast unguarded | DISMISSED — realism caveat | — |
| A27-2 | 1 | INFO | decodeParameters doesn't re-validate | DISMISSED | — |
| A28-P2-2 | 2 | LOW | onBurn underflow not tested | FIXED — added test | PR5 |
| A28-P2-3 | 2 | INFO | No fuzz on effectiveTotalSupply | DEFERRED | — |
| A26-P4-1 | 4 | LOW | forge-lint disable misplaced in LibRebase | FIXED | PR4 |
| A28-P4-1 | 4 | LOW | forge-lint disable misplaced in LibTotalSupply | FIXED | PR5 |
| A_FMT-1 | 4 | LOW | forge fmt diffs in 5 files | FIXED — `gt`-aware fmt per PR | PR1, PR2, PR4, PR5 |
| A01-P3-1 | 3 | LOW | Facet event NatSpec | FIXED | PR1 |
| A01-P3-2 | 3 | LOW | Facet "must be delegatecalled" not stated | FIXED | PR1 |
| A03-P3-1 | 3 | LOW | AccountMigrated event lacks @param | FIXED | PR4 |
| A20-P3-1 | 3 | LOW | Interface silent on completion semantics | FIXED via A01-P5-1 | PR6 |
| A20-P3-2 | 3 | INFO | Interface lacks action type constants | DEFERRED — INFO | — |
| A21-P3-1 | 3 | LOW | head()/tail() lack NatSpec | FIXED | PR1 |
| A21-P3-2 | 3 | INFO | Storage struct field interaction undocumented | FIXED — small @dev block | PR5 |
| A27-P3-1 | 3 | LOW | validateParameters NatSpec/impl mismatch | FIXED via A27-1 | PR3 |
| A27-P2-1 | 2 | LOW | Negative-coefficient branch untested | FIXED | PR3 |
| A27-P2-2 | 2 | LOW | Near-zero multiplier untested | FIXED via A27-1 | PR3 |
| A21-P2-1 | 2 | LOW | Tied effectiveTime ordering untested | DEFERRED — INFO weight | — |
| A22-P2-1 | 2 | LOW | prevOfType COMPLETED/PENDING untested | FIXED | PR2 |
| A01-P2-1 | 2 | LOW | scheduleCorporateAction auth path uncovered | DEFERRED — needs mock authorizer scaffolding, large for this audit | — |
| A01-P2-3 | 2 | LOW | Facet *OfType getters not tested via facet | FIXED | PR6 |
| A01-P2-4 | 2 | LOW | prevOfType filter coverage | FIXED via A22-P2-1 | PR2 |
| A23-P2-1 | 2 | LOW | No direct LibERC20Storage test | FIXED via A23-1 | PR4 |

## Triage policy notes

Items marked **DEFERRED** are not fixed in this audit run. They are real but either (a) require larger architectural discussion (A01-1 / A21-1: authorizer surface area), (b) require new infrastructure not justified by current code (A01-P2-1: mock authorizer rig — superseded once a real authorizer is wired into the vault tests), or (c) are speculative until hypothesised future work lands (A26-P2-2: non-split action type interspersing).

Items marked **DISMISSED** are correct-as-is by design.

Items marked **FIXED** were applied to the originating PR in the stack and propagated upward via `gt restack`. Each PR was rebuilt and re-tested locally before `gt submit`.
