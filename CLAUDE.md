# CLAUDE.md

Only hazards an agent would get **wrong** live here. Architecture, dependency
lists, CI commands, compiler settings and deployment history are all readable
from the repo and are deliberately absent — do not re-add them.

- **Never declare a state variable on `StoxCorporateActionsFacet`.** The facet
  is delegatecalled by the vault, so storage declared on it writes the VAULT's
  slots and silently corrupts live production storage. Facet state belongs in an
  ERC-7201 namespaced library struct (see `src/lib/LibCorporateAction.sol`).

- **Address and codehash constants in `LibProdDeploy*` / `LibProdBeacons*` are
  an audit trail of what is deployed on chain.** Never delete one for looking
  unreferenced, and never update one to match a newer deployment — a redeploy
  gets a new release-tag suffix or a new library, keeping the old values intact.

- **Every compiler setting stays in the single `[profile.default]`.** Tests
  assert `addr.codehash` against constants derived from _deployed_ bytecode, so
  a second profile compiling with different optimizer settings breaks every
  codehash assertion. Regenerating the pins to get green commits wrong
  constants; fix the profile split instead.

- **`forge update` is the git-submodule command and silently does nothing
  here.** Dependencies are Soldeer packages. `forge soldeer update` moves them
  and regenerates `remappings.txt`, but the pinned version is part of every
  import prefix (`rain-vats-0.1.6/…`) and Soldeer does not rewrite imports —
  update those by hand in the same commit.

- **Production `onlyOwner` / `_ADMIN` surfaces are held by a governance
  timelock, not by the token-owner Safe.** A script touching one routes through
  `timelock.schedule(...)` → delay → `timelock.execute(...)`, and resolves the
  address only via `LibTimelockInvariants.timelockForChainId`. Role model and
  runbook: `docs/TIMELOCK.md`.
