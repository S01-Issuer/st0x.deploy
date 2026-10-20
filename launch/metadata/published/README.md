# Published metadata recovered from chain

Verbatim copies of metadata actually emitted to the MetaBoard, recovered by
decoding the Rain Meta document in the log data.

These are **records, not inputs**. They use the older webapp schema
(`primary_ticker` carries an exchange suffix, `inception_date` instead of
`ipo_date`, `category` and `dividend_paying_frequency` present, counterparty
names blank), so they will not pass `cd-plan` validation and are deliberately
kept out of the repo root where CD picks up `metadata-*.json`.

| File                  | Token | Emitted    |
| --------------------- | ----- | ---------- |
| `ibhg.published.json` | tIBHG | 2026-03-31 |

Every other pre-`sft-ops` token has no published metadata at all — see the scan
noted in the launch runbook.
