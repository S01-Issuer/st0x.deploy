# A03 — Pass 5 (Correctness / Intent): StoxReceiptVault

## Findings

### A03-P5-1 — Pointer to Pass 1 finding A03-1

The contract NatSpec at lines 11-22 claims "Migration is lazy: each account's stored balance is rasterized to the current rebase version on first interaction (transfer, mint, burn)." The implementation does this only for accounts with non-zero stored balance; fresh accounts are silently skipped, breaking the documented invariant. This is the same finding as `pass1/StoxReceiptVault.md::A03-1`. The NatSpec accurately describes the intended behavior; the implementation doesn't deliver it.

**Severity:** CRITICAL (as A03-1).

No separate fix file — fixing A03-1 makes the implementation match the doc, closing this finding.
