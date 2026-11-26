# GLEIF ISIN sample

`every-100th-isin.txt` is the `ISIN` column of every 100th row, from the first,
of GLEIF's ISIN-to-LEI relationship file `isin-lei-20261125T081511.zip`
(published 2026-11-25T08:15:11Z, retrieved 2026-11-26, sha256
`e4a58c375759daa1898667d05f3b431c00beb28e997b5b72f81523b9088f9fb7`), one per
line:

```sh
curl -sSfL https://mapping.gleif.org/api/v2/isin-lei/884cbf0b-0075-483f-8876-4480c9320ffd/download \
  | gzip -dc \
  | awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "ISIN") c = i; next } (NR - 2) % 100 == 0 { print $c }'
```
