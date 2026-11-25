/* 0. weighting */ 
using-words-from 0xd88B84a6471f5d21212C614945321f73e4b35919

:ensure(
  binary-equal-to(lead() 0xB05Da3f2e145C6b156D97872386Bc8645B34b668)
  "Lead attestation missing"
),

symbol: underlying-symbol(mint-token()),
price-domain: [eip712-domain-separator name "prices" version "1"],
:ensure(
  binary-equal-to(lead-domain() price-domain)
  "Lead domain mismatch"
),

:ensure(
  binary-equal-to(lead-source() "alpaca")
  "Lead source mismatch"
),

:ensure(
  binary-equal-to(lead-symbol() symbol)
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

lead-time-key: hash("lead-time" symbol),
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
