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
  Exception: an `address(0)` placeholder slot for a chain whose clone is not
  deployed yet is pinned in place in `script/Build.sol` once the deploy lands,
  and its placeholder test is replaced by the pin. Pin a clone before its deploy
  only at a CloneFactory open-salt address, which commits to the implementation
  and init data, with a test that re-derives it. Never pin a factory nonce
  (CREATE) address before the deploy: any caller can take it.

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
  timelock, not by the token-owner Safe.** Once a surface has moved, the Safe
  can no longer call it directly: a script touching it goes
  `timelock.schedule(...)` → delay → `timelock.execute(...)`, resolving the
  address only via `LibTimelockInvariants.timelockForChainId`. How the timelock
  works: `docs/TIMELOCK.md`. Exception: the tQSEP vault
  (`LibTokenInvariants.QSEP_RECEIPT_VAULT`) is outside the token table, so its
  `owner()` is still the Safe and vault `onlyOwner` calls (`setAuthorizer`
  included) are direct Safe transactions. Even on the fleet authoriser, tQSEP
  mint and burn authority is NOT delay-gated: the Safe can point the vault at
  another authoriser in one transaction until its `owner()` moves to the
  timelock.

- **Every chain's root line holds every migration, 0G included.** The registry
  is immutable, so a line that differs on one chain can never be fixed. 0G ran
  none of the history the backfill records (`LibStoxMigrations.withoutHistory`):
  each of those declarations is record-only on 0G, and the backfill writes them
  there in the off-Base order. Declare a new migration onto the line's current
  head on every chain, and give it a record-only bundle on a chain where it has
  nothing to do. Insert it before the first unrecorded migration instead, moving
  that migration's `onto`, only when live reads on every chain, repeated right
  before the inserting PR merges, prove nothing recorded, queued or approved it
  or anything after it: `LibStoxMigrations.head()`, the Safe Transaction Service
  queue at or above the live nonce, and `approvedHashes(owner, safeTxHash)` for
  every owner and authored artifact at that nonce (an on-chain `approveHash`
  skips the service). Until the inserted record lands on a chain, nobody signs
  there an artifact of the moved migration authored before the change.
