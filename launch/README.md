# Launch inputs

The ledger, allowlist, dedicated-authoriser pins and `metadata/` are copies of
the sft-ops inputs at sft-ops commit `ee39d0d`. sft-ops stays the source of
truth and keeps launching tokens until the cutover, so these copies go stale.

Before the cutover, diff this directory against the current sft-ops inputs and
re-sync it. A token sft-ops launched after the copy is missing from
`launches.json`, and the planner would plan it again (tFGI already shows this;
see `audit/known-false-positives.md`).

`test/fixtures/launch/` holds a frozen copy of the `ee39d0d` ledger and metadata
for the parity test. Apply any redaction of `launches.json` to
`test/fixtures/launch/launches-ee39d0d.json` in the same commit.
