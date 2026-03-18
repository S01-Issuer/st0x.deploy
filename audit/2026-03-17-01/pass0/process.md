# Pass 0: Process Review

Date: 2026-03-17

## Documents Reviewed

- `README.md` — only first-party process document
- `foundry.toml` — build configuration
- `flake.nix` — Nix development environment
- `REUSE.toml` — license metadata
- No `CLAUDE.md` or `AGENTS.md` exists

## Findings

### P0-1: No CLAUDE.md project instructions [MEDIUM]

There is no `CLAUDE.md` file providing project-specific instructions for AI-assisted development sessions. This means future sessions have no guidance on:
- Project structure and conventions
- Build/test/deploy commands
- Security-sensitive areas
- Naming conventions
- Test file location patterns

Without this, each session must rediscover the project layout, increasing the chance of convention violations (e.g., wrong import style, missed test patterns).

### P0-2: README.md is minimal and lacks operational guidance [LOW]

`README.md` contains only:
```
Deployments and extensions for Ethgild that are domain specific for st0x.
For example, corporate actions for shares will need to be implemented above the
standard RWA tokenization logic.
```

Missing information:
- No build/test instructions (`forge build`, `forge test`)
- No mention of Nix flake for dev environment setup
- No description of the `src/`, `script/`, `test/` directory structure
- No mention of the Foundry toolchain or Solidity 0.8.25 requirement
- No description of the dependency on `ethgild` submodule
- No deployment process documentation
- "Corporate actions for shares will need to be implemented" reads as future intent, not current state — unclear if this is implemented yet
