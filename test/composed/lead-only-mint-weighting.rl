/* 0. weighting */ 
using-words-from 0x28Df1347eae93f7d85bCBe4b6605034a2F6F1cBD

:ensure(
  binary-equal-to(lead() 0xB05Da3f2e145C6b156D97872386Bc8645B34b668)
  "Lead attestation missing"
),

price-domain: [eip712-domain-separator name "prices" version "1"],
:ensure(
  binary-equal-to(lead-domain() price-domain)
  "Lead domain mismatch"
),

:ensure(
  binary-equal-to(lead-source() "alpaca")
  "Lead source mismatch"
),

vault-symbol: mint-symbol(),
symbol-scale: uint256-power(0x0100 bitwise-and(vault-symbol 0x1f)),
symbol-first: uint256-div(vault-symbol symbol-scale),

:ensure(
  binary-equal-to(symbol-first 0x74)
  "Vault symbol has no t prefix"
),
ticker: uint256-sub(vault-symbol uint256-mul(symbol-first symbol-scale) 0x01),
:ensure(
  binary-equal-to(lead-symbol() ticker)
  "Attestation for another token"
),

:ensure(
  binary-equal-to(lead-currency() "USD")
  "Price not in USD"
),

:ensure(
  agree(
    600 0
    now() lead-time()
  )
  "Times disagree"
),

lead-time-key: hash("lead-time" ticker),
:ensure(
  greater-than-or-equal-to(lead-time() get(lead-time-key))
  "Lead time went backwards"
),
:set(lead-time-key lead-time()),

:ensure(
  less-than-or-equal-to(100 lead-price() 1000)
  "Price outside bounds"
),

value: mul(mint-amount() lead-price());
