# A21 — Pass 4 (Code Quality): LibCorporateAction

## Findings

### A21-P4-1 — `CorporateActionStorage` mixes ownership-of-concern with `LibTotalSupply`

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:49-73`

Three of the seven storage fields (`unmigrated`, `totalSupplyLatestSplit`, `totalSupplyBootstrapped`) belong conceptually to `LibTotalSupply` but live in `LibCorporateAction`'s storage struct. They were added together in PR5 (commit `57c3579`). The reason is that `LibTotalSupply` shares the same ERC-7201 namespace and there's no second namespace for the totalSupply tracking.

Two ways to clean this up:
1. Add a separate ERC-7201 namespace `rain.storage.corporate-action.total-supply.1` with its own location constant, and move the three fields into a new `TotalSupplyStorage` struct exposed by `LibTotalSupply.getStorage()`.
2. Leave the fields where they are and add a `@dev` block on the storage struct documenting that LibTotalSupply owns them.

Option 2 is the lower-friction fix and is captured in A21-P3-2. Option 1 is a separate refactor not required by the audit. INFO; no fix file.

### A21-P4-2 — Linked-list insertion is O(n) via tail walk

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:131-152`

`schedule()` walks backwards from `tail` to find the insertion point. For most-recent-first insertions (the common case for stock splits) this is O(1); for backdated inserts on a long list it's O(n). Corporate actions are infrequent so this is fine, but worth noting in case the list grows large or a high-frequency action type is added later. INFO.
