# Wikidata ISIN (P946) values

Every distinct value of every
[ISIN (P946)](https://www.wikidata.org/wiki/Property:P946) statement on
Wikidata, of any rank. Wikidata's structured data is
[CC0 1.0](https://www.wikidata.org/wiki/Wikidata:Licensing).

- Source: the Wikidata Query Service, https://query.wikidata.org/sparql
- Query: `SELECT DISTINCT ?isin WHERE { ?item p:P946/ps:P946 ?isin }`
- Retrieved: 2026-11-26
- Split: `accepted.txt` holds the values that are 2 of `A-Z`, 9 of `A-Z` and
  `0-9`, then a digit that passes the Luhn check over the letters expanded to
  `A` = 10 … `Z` = 35. `rejected.txt` holds the rest. Both are one value per
  line, byte-sorted.

| File           | Values | sha256                                                             |
| -------------- | -----: | ------------------------------------------------------------------ |
| `accepted.txt` | 10,260 | `011a0da331036b7fdde1242aff1f7bb03da9384add5a72cbd0ed981fd2f745c8` |
| `rejected.txt` |     60 | `e7a1e8bffd9a223b6d3389cf8c94698e8ebe272e851db008cba65495973ff152` |

Regenerate from the repo root, inside `nix develop`, after deleting both files:

```sh
export LC_ALL=C
curl -sSfL --retry 3 -G \
  -H 'Accept: application/sparql-results+json' \
  -A 'st0x.deploy (https://github.com/S01-Issuer/st0x.deploy)' \
  --data-urlencode 'query=SELECT DISTINCT ?isin WHERE { ?item p:P946/ps:P946 ?isin }' \
  https://query.wikidata.org/sparql \
  | jq -r '.results.bindings[].isin.value' \
  | sort -u \
  | awk -v dir=test/fixture/wikidata-p946 '
      function wellFormed(s,   digits, i, c, d, sum) {
        if (length(s) != 12 || s !~ /^[A-Z][A-Z][A-Z0-9]*[0-9]$/) return 0
        for (i = 1; i <= 12; i++) {
          c = substr(s, i, 1)
          digits = digits (c ~ /[A-Z]/ ? index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c) + 9 : c)
        }
        for (i = length(digits); i > 0; i--) {
          d = substr(digits, i, 1) * ((length(digits) - i) % 2 + 1)
          sum += d > 9 ? d - 9 : d
        }
        return sum % 10 == 0
      }
      { print > (dir "/" (wellFormed($0) ? "accepted" : "rejected") ".txt") }'
```
