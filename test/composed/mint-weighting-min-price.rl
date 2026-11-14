/* 0. weighting */ 
using-words-from 0x28Df1347eae93f7d85bCBe4b6605034a2F6F1cBD

:ensure(
  binary-equal-to(lead() 0xB05Da3f2e145C6b156D97872386Bc8645B34b668)
  "Lead attestation missing"
),

:ensure(
  binary-in<2>(
    attestor<0>() attestor<1>()
    0xAC8060AD1Dd83600ecA7354FC69C3743c9b92Fee 0x728A622778F567db1554aD121a4066e62925fd4d 0x9b4Fe8400530Aec2C9dB758195E355F8b37d921b 0x9821d24af0dD88AE2a655e247E5eC673c8aA2F8E 0x13943A2e84e66a28FfF57641cF769361F410C0C1 0x260976eDD64D602989E7df01B2860f4b15432402
  )
  "Attestor not allowlisted"
),

price-domain: [eip712-domain-separator name "prices" version "1"],
:ensure(
  binary-equal-to(lead-domain() price-domain)
  "Lead domain mismatch"
),
:ensure(
  binary-equal-to(attestor-domain<0>() attestor-domain<1>() price-domain)
  "Attestor domain mismatch"
),

:ensure(
  binary-equal-to(lead-source() "alpaca")
  "Lead source mismatch"
),
:ensure(
  binary-in<2>(
    attested-source<0>() attested-source<1>()
    "yahoo" "alpaca"
  )
  "Pool source not allowlisted"
),

:ensure(
  binary-unique(lead() attestor<0>() attestor<1>())
  "Same operator twice"
),

/* Ticker: the IntOrAString vault symbol less its leading `t`. */
vault-symbol: mint-symbol(),
symbol-scale: uint256-power(0x0100 bitwise-and(vault-symbol 0x1f)),
symbol-first: uint256-div(vault-symbol symbol-scale),

:ensure(
  binary-equal-to(symbol-first 0x74)
  "Vault symbol has no t prefix"
),
ticker: uint256-sub(vault-symbol uint256-mul(symbol-first symbol-scale) 0x01),
:ensure(
  binary-equal-to(
    lead-symbol() attested-symbol<0>() attested-symbol<1>()
    ticker
  )
  "Attestation for another token"
),

:ensure(
  binary-equal-to(
    lead-currency() attested-currency<0>() attested-currency<1>()
    "USD"
  )
  "Price not in USD"
),

:ensure(
  agree(
    600 0
    now() lead-time() attested-time<0>() attested-time<1>()
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
  agree(
    0 0.01
    lead-price() attested-price<0>() attested-price<1>()
  )
  "Attestors disagree"
),

:ensure(
  less-than-or-equal-to(1 lead-price() 1000)
  "Price outside bounds"
),

value: mul(mint-amount() lead-price());
