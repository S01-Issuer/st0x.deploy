# Base token launch

The Base token launch ported from sft-ops: the metadata and launch phases of
sft-ops `docs/runbooks/S01-LAUNCH.md`, on this repository's paths. Every other
phase (replication to other chains, permissions, handoff, launch day) is
unchanged and stays in that runbook.

**Status: dry-run only.** Until the cutover, sft-ops launches every token. Here,
the `deploy` job of `.github/workflows/deploy-sft.yaml` is off: the repository
variable `LAUNCH_ENABLED` is unset and the launch signer's key is not
configured. Merging a metadata file runs `validate` and `dry-run`, so the same
file can be checked here while sft-ops launches it. The inputs under `launch/`
are copies of sft-ops's and are re-synced at cutover.

Step format: `- [ ] Step — owner · how · done-when`

## Metadata

`plan()` checks `country.iso`, `isin`, `asset_type` and the counterparties.
Everything below is what it cannot check.

- [ ] **Asset class noted** — Alastair · tag each ticker equity / ETF / CEF /
      ADR / DR / leveraged before generating · every ticker tagged.
- [ ] **ISIN sourced** — Alastair · `EODHD_API_KEY` in the environment looks it
      up at generation (20 a day, free tier). Otherwise take it from the issuer
      prospectus or the Cboe listing page. US format `US<CUSIP><check>`. For a
      US depositary, use the DR's ISIN, not the home-market one · an ISIN for
      every ticker.
- [ ] **Generate** — Alastair · one per ticker, from the repository root:

      ```bash
      (cd launch/ffi && npm ci --ignore-scripts)
      forge script script/GenerateMetadata.s.sol --ffi \
        --sig 'run(string,string,string)' HOOD equity US7707001027
      ```

      Use `etf` for closed-end funds too, which Yahoo reports as equity ·
      `launch/metadata/<ticker>.json` exists for every ticker.
- [ ] **Review the generator output** — Alastair · check by class against the
      reference file:

      | Class | Check | Reference |
      | --- | --- | --- |
      | Any | `country.iso` non-empty, ISO 3166-1 alpha-2 | — |
      | Equity / ETF | `name` is the asset name, not the ticker | `launch/metadata/hood.json` |
      | CEF | `asset_type` is `ETF` | `launch/metadata/pty.json` |
      | ADR | `name` ends `(ADR)`; `description` opens with ADS ratio, depositary bank and US exchange; `ipo_date` is the US listing date; `country.iso` is the underlying issuer's | `launch/metadata/tsm.json` |
      | NY registry share / DR | the same four fields as an ADR, naming the registry-share line | `launch/metadata/tsm.json` |
      | Leveraged | `description` states the daily reset and volatility decay | `launch/metadata/tqqq.json` |

      Non-US home-market listings add `Freedom Finance` to
      `offchain_counterparties` by hand.

## Launch on chain

Merging a new `launch/metadata/<ticker>.json` to `main` launches that token.
Dispatching the workflow with a file list is the only other way in.

- [ ] **Dedicated-authoriser tokens only: pin the authoriser** — Alastair · a
      token listed in `launch/dedicated-authorisers.json` (today: `tMC`) lands
      on its own authoriser, never on the shared one. `plan()` refuses it while
      the pinned `authorizer` is the zero placeholder. Once the authoriser is
      deployed, set `authorizer` and `deployBlock` (the block that created it),
      and add the address to `launch/allowlist.json` with role `authorizer`,
      chainId `8453`, in the metadata PR or one merged before it. Set
      `minterGrantPending: true` until the minter holds `DEPOSIT` and `WITHDRAW`
      on the authoriser; while that flag is set the pre-flight skips the minter
      role check (as sft-ops does for `tMC`). Clear the flag once the Safe grant
      bundle has run. The pre-flight then proves the authoriser was created at
      `deployBlock`, replays every role grant and revoke since, and refuses
      unless `DEPOSIT` and `WITHDRAW` are held by the minter and the token-owner
      Safe and nobody else · the plan logs `authorizer=<addr> (dedicated, …)`.
- [ ] **Open the metadata PR** — Alastair · one file per new token, nothing else
      in the diff bar the pin above · PR open, `launch-ffi-test` green.
- [ ] **Get a review** — whoever did not open the PR · check the file against
      the table below: the symbol, name, type and certify-until it gives. The
      `validate` summary shows the same plan only after the merge · approved.
- [ ] **Merge** — Alastair · reviewed and green. **Once `LAUNCH_ENABLED` is set,
      merging broadcasts to mainnet** · merged to `main`.
- [ ] **Watch the run** — Alastair and the reviewer · each token is simulated,
      then deployed, cloned and wired in three broadcasts, then recorded and
      checked on chain · run green, addresses in the summary. A `validate` or
      `dry-run` failure means nothing was broadcast: fix the file if needed,
      merge, then dispatch it as below, since a changed file does not trigger a
      launch. A cancelled `deploy` can have mined transactions and may not
      upload its artifacts. Reconcile the signer's transactions and on-chain
      state before dispatching any token again; recover a partial launch by hand
      as below. If `Record` exits 0 but `launch/launches.json` is unchanged (for
      example an RPC error during `record()`), rebuild the ledger from the run's
      `launch-record` artifact before any new dispatch. Never use the re-run
      buttons on `deploy-sft`: a re-run does not run `deploy`.
- [ ] **Open and merge the ledger PR** — Alastair · the run pushes
      `cd/ledger-<run_id>` with the updated `launch/launches.json` and prints
      the compare link in the summary · merged.
- [ ] **Dispatch a batch again** — Alastair · only after the ledger PR of the
      stopped run is merged: `plan()` reads the ledger on `main`, so a token
      whose row is still on the unmerged branch launches a second time. The push
      trigger does not fire again once the file is on `main`: re-run with
      `Actions → deploy-sft → Run workflow`,
      `files = launch/metadata/<a>.json launch/metadata/<b>.json`, listing only
      tokens with nothing on chain · run green.

**A token that stopped partway** is listed in the run summary with its vault
address and the stage it reached, as sft-ops's "BATCH STOPPED" report does. It
has no ledger row unless its landing authoriser was set, and it is owned by the
launch signer. Never list its file in a re-run: the new run has none of the
stopped run's stage files and deploys another vault for the symbol. A `wire`
stage cannot be re-run either, since it refuses a vault whose authoriser was
already changed. Finish or abandon the token by hand from the run's
`launch-record` artifact, which holds every stage's receipts, the payloads and
the ledger the run wrote, then add or correct its ledger row in a PR.

**Everything is derived from the metadata file:**

| Argument      | Source                               |
| ------------- | ------------------------------------ |
| symbol        | `t` + `primary_ticker`               |
| name          | `name` + `" ST0x"`                   |
| schema        | `asset_type`: `Equity` or `ETF`      |
| certify-until | the date `validate` planned + 1 year |
| owner         | the production Safe, constant        |

The Safe is the owner sft-ops hands every token to. `docs/TIMELOCK.md` expects
new Base vaults to go to `STOX_GOVERNANCE_TIMELOCK` instead; that change is out
of scope for this port and must be decided before `LAUNCH_ENABLED` is set.

**The run refuses to launch** when the symbol is already live or retired in
`launch/launches.json`, the name is the ticker or symbol, `asset_type` is
neither `Equity` nor `ETF`, `country.iso` is empty, the ISIN is missing or
malformed, `offchain_counterparties` is not exactly `AlpacaDB Inc` +
`Clear Street LLC` (plus `Freedom Finance` for a non-US listing), the owner is
not allowlisted, a dedicated-authoriser token has no allowlisted authoriser
pinned, or the simulation's owner, authoriser or exclusive-minter checks fail.

**Verification reads the chain, not the ledger.** `owner()` must be the
production Safe `0xe70d821f…d611`, `isCertificationExpired()` false, and
`authorizer()` the shared authoriser
`0x315b16faa6eE413faBCa877d3851B3818369f0cD`, or, for a dedicated-authoriser
token, its pinned authoriser. A dedicated token goes from the temporary
certification authoriser straight to its own; it is never wired to the shared
one, even briefly.
