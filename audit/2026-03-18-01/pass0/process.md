# Pass 0: Process Review — 2026-03-18-01

Date: 2026-03-18

## Context

This audit captures process defects observed during the 2026-03-17 audit and subsequent Zoltu migration work. Each finding represents a behaviour that a future session could repeat without explicit guidance.

## Findings

### P0-1: No guidance on library pragma convention [MEDIUM]

Libraries use `^` pragma intentionally for wider compatibility when consumed by other projects. Concrete contracts use `=` exact pin. Without documenting this, sessions will flag the inconsistency and attempt to "fix" it.

### P0-2: No guidance on deployment constant preservation [MEDIUM]

Production deployment address constants in `LibProdDeploy` serve as an audit trail of deployed contracts, not as code dependencies. Sessions will flag unreferenced constants as dead code and attempt to remove them.

### P0-3: No guidance on test contract file placement [LOW]

Mock/helper contracts used in tests belong in `test/concrete/`, libraries in `test/lib/`. Without this, sessions will inline mocks in test files or place them incorrectly.

### P0-4: No guidance on immutable naming convention [LOW]

Rain ecosystem uses `iCamelCase` for immutables (per rain.orderbook), not `I_SCREAMING_SNAKE`. Without this, sessions will follow the ethgild pattern which uses the old convention.

### P0-5: No guidance to prefer forge tests over cast queries [MEDIUM]

When needing on-chain data (codehashes, addresses, bytecodes), sessions should write forge fork tests rather than manual `cast` queries. Tests are durable verification; cast queries are one-off.

### P0-6: No guidance on fork test block pinning [LOW]

Fork tests must use pinned block numbers with archival RPCs. The solution to "historical state not available" is a better RPC, not removing the pin.

### P0-7: No guidance on creation vs runtime bytecode [LOW]

Bytecode constants for reproducible deployment must be creation code (not runtime code). Creation code enables redeployment; runtime code varies with constructor args/immutables.

### P0-8: No guidance on single-file constants [LOW]

All prod deploy constants (addresses, codehashes, bytecodes) belong in a single file per version, not split across multiple files.

### P0-9: No guidance on slither configuration [MEDIUM]

- Don't filter all of `lib/` (too broad — hides direct dependency findings)
- Don't exclude `test/` from analysis
- Always explain why when adding `slither-disable` annotations
- Prefer computing values in Solidity (e.g., `keccak256()` for event topics) over hardcoding hex literals

### P0-10: No guidance on checking repo state before proceeding [LOW]

Sessions should verify the current repo state (git status, existing files, remappings) before assuming and proceeding with changes. Don't read reference files from other repos before confirming local state.

### P0-11: No guidance on versioned deploy libraries [MEDIUM]

Contracts are upgradeable — each deployment version needs its own `LibProdDeployVN.sol`. Sessions should create new version files rather than modifying existing ones.

### P0-12: No guidance on dependency management ownership [LOW]

Sessions should not add git submodules or modify `foundry.toml` remappings — the user manages dependencies. Wait for the user to set up deps before proceeding.

### P0-13: No guidance on skill installation [LOW]

Skills repos should have an `install.sh` script for symlinking to `~/.claude/skills/`. Don't manually create symlinks.

### P0-14: No guidance on distinguishing proxies from implementations [LOW]

When tracking deployed contract addresses, clearly distinguish proxy instances from implementation contracts. Verify on-chain which is which rather than assuming from constant names.

### P0-15: No guidance on changelog maintenance [LOW]

`CHANGELOG.md` must be updated when making contract source changes. Document behavioural differences between deployment versions.
