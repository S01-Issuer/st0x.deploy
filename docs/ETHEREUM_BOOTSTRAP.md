<!--
SPDX-License-Identifier: LicenseRef-DCL-1.0
SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
-->

# Ethereum mainnet bootstrap runbook

Ordered checklist for standing up the full ST0x production stack on Ethereum
mainnet with policies, names, symbols and permissions matched to Base (RAI-1095
/ RAI-1096; parity thereafter enforced by the cross-chain parity pin, RAI-1097).
Ethereum bootstraps directly at V4 — there is no pre-V4 history on this chain
and none should ever be created.

Every step is gated by a pre-flight or a pin; run them in order. Steps marked
**[pin PR]** land a reviewed PR that hydrates a placeholder constant — the
pin-before-modify pattern: nothing that mutates chain state against a pinned
address runs until the pin is a hand-reviewed literal.

## 0. Prerequisites

- [ ] The V4 corporate-actions stack is merged (this file ships stacked on it)
      and the V4 suites have executed on Base.
- [ ] `ETHEREUM_RPC_URL` available locally; `RPC_URL_ETHEREUM_FORK`
      secret/variable added to the repo once the rainix workflows accept it (see
      the rainix PR referenced in the stack).
- [ ] Deployer EOA funded with ETH on Ethereum mainnet for the Zoltu broadcasts
      (RAI-1103 covers operational-wallet gas more broadly).

## 1. Core V4 suites (deterministic, permissionless)

The Zoltu factory is live on Ethereum at the canonical
`LibRainDeploy.ZOLTU_FACTORY` address (verified 2026-07-06, RAI-1211).
`LibStoxDeployNetworks.supportedNetworks()` already includes Ethereum, so each
suite run broadcasts to Base (no-op, already deployed) and Ethereum (fresh
deploy at the identical address):

```bash
DEPLOYMENT_KEY=<hex> DEPLOYMENT_SUITE=<suite> forge script script/Deploy.sol
```

Run the ten suites in the dependency order documented in `CLAUDE.md` §
Deployment (implementations → beacon → set-deployers → unified deployer →
authorisers → facet).

- [ ] All ten suites broadcast; `testProdDeployEthereumV4` goes green.

## 2. Rain CloneFactory

The canonical Rain `CloneFactory`
(`LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS`,
`0x444acC29d63fa643E8adCC35FD9aa6DE111dCb39`) is **not** deployed on Ethereum as
of 2026-07-06. It is Zoltu-deterministic and permissionless — deploy it from the
rain-factory repo. The clone-deploy pre-flight (`CloneFactoryNotDeployed`)
blocks step 5 until this lands.

- [ ] CloneFactory deployed on Ethereum at the canonical address with the pinned
      codehash.

## 3. Ethereum principals (Safe + service signer)

The principals are **shared across chains, not per-chain.** The token-owner Safe
is reproduced at its **exact Base address** on Ethereum (§ 3a) and the issuance
service signer is the Base signer (Josh, 2026-07-07), so there is no per-chain
principal pin to hydrate: `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE` (the Safe)
and `LibAuthoriserInvariants.GRANTEE_SERVICE_1C66` (the signer) are the same
pins on every chain, and `LibInvariants.assertProductionState` validates every
chain against them. The one remaining bootstrap gate is standing up the Safe
proxy on Ethereum at that shared address (RAI-1109, § 3a).

- [x] **Safe address decision (RAI-1109):** (A) reproduce Base's address —
      chosen (Josh, 2026-07-07). Automated in § 3a: deploy the genesis proxy
      (Base's Safe was created as v1.3.0, whose factory + singleton are live on
      Ethereum), then replay to the current policy. Option B (fresh v1.4.1 Safe,
      different address, current policy in one tx) was the alternative.
- [ ] Ethereum token-owner Safe created and policy-aligned — Safe v1.4.1, same
      owner set and threshold as Base (the shared
      `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE` + owner/threshold pins),
      reproduced at the shared Base address (§ 3a). No pin PR: the pins are
      already Base's; the forcing-function test
      `DeploySafeEthereumTest.testEthereumSafeMatchesBasePolicy` is red until
      the live Ethereum Safe satisfies them.

### 3a. Deploy the matched-address Safe (Option A)

`script/20260707-deploy-safe-ethereum.s.sol` reproduces the Base token-owner
Safe at its **exact Base address** on Ethereum by replaying the genesis creation
call pinned in `LibStoxSafeGenesis` (recovered from the Base creation tx). The
Safe address is `CREATE2(factory, keccak(keccak(initializer) ++ saltNonce), …)`,
so the same inputs reproduce the same address. The canonical Safe **v1.3.0**
factory + singleton (the versions the Base Safe was created with — it was later
upgraded to v1.4.1) are already live at their usual addresses on Ethereum.

```bash
DEPLOYMENT_KEY=<hex> ETHEREUM_RPC_URL=<url> forge script \
  script/20260707-deploy-safe-ethereum.s.sol \
  --rpc-url ethereum --sig 'run()' --broadcast
```

The script asserts the produced proxy equals
`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE` before returning; the fork test
`DeploySafeEthereumTest` proves the reproduction against a live Ethereum fork.

- [ ] Matched-address Safe deployed on Ethereum.

**Then align policy to Base (genesis → current).** The reproduced Safe lands in
its GENESIS state — **3 owners, threshold 2, on v1.3.0**. Base has since moved
to **6 owners, threshold 3, on v1.4.1**. Reaching parity is a replay authored as
Safe bundles and signed by the **genesis** owners
(`LibStoxSafeGenesis.GENESIS_OWNER_1..3`):

- [ ] Upgrade the singleton v1.3.0 → v1.4.1 (and swap the fallback handler to
      the v1.4.1 `CompatibilityFallbackHandler`).
- [ ] Add the 3 later owners and raise the threshold to 3, matching Base's
      current `getOwners()` / `getThreshold()`.
- [ ] Re-run `LibSafeInvariants.assertAll` against the Ethereum Safe — it must
      satisfy the same v1.4.1 singleton/proxy codehash + owner-set + threshold
      pins as Base.

> Trade-off vs Option B (fresh v1.4.1 Safe, current policy, one tx): Option A
> gives the identical address on every chain but requires this genesis replay
> through the original signers. Chosen per Josh 2026-07-07.

## 4. Fireblocks / custody

- [ ] Ethereum contract + wallet addresses whitelisted (RAI-1100). The
      core-contract addresses are known ahead of execution (deterministic); file
      this the moment the chain decision is made.

## 5. Authoriser clone deploy — RAI-1096

The V4 authoriser clone is deployed by the **chain-agnostic** script
`script/20260619-deploy-v4-authoriser-clone.s.sol` — the same script Base uses.
It is network-agnostic (`deployer = msg.sender`, "CloneFactory missing on this
network" pre-flight), so Ethereum reuses it verbatim by pointing `--rpc-url` at
Ethereum; there is no Ethereum-specific clone script. The deployer key
broadcasts a single run that deploys the clone, grants it the role map, then
**renounces** the deployer's own `_ADMIN` roles so no EOA retains root over the
grants.

```bash
DEPLOYMENT_KEY=<hex> ETHEREUM_RPC_URL=<url> forge script \
  script/20260619-deploy-v4-authoriser-clone.s.sol \
  --rpc-url ethereum --broadcast
```

- [ ] Prerequisite: the canonical Rain `CloneFactory` is deployed on Ethereum
      (§ 2) — the script's `CloneFactoryNotDeployed` pre-flight blocks
      otherwise.
- [ ] Clone deployed on Ethereum; deployer roles renounced.
- [ ] **[pin PR]** Hydrate
      `LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM`
      (hand-maintained — the clone address is non-deterministic, so it is
      provided post-deploy, not generated) with the real clone address. Both
      chains' clone addresses live in `LibProdAuthoriserClones`; the codehash is
      shared with Base (the EIP-1167 runtime embeds the impl address, identical
      cross-chain) and stays generated in `LibProdDeployV4`.

> The clone script's "already hydrated" guard is network-aware: it reads
> `LibProdAuthoriserClones.cloneForChainId(block.chainid)`, so it checks the
> Base pin on Base and the Ethereum pin on Ethereum. Hydrating Base's clone
> therefore does not wrongly refuse the Ethereum run.

## 7. Token deployment (matched names / symbols / policies)

For each of the 20 production tokens (the `underlying` keys in
`LibTokenInvariants.productionTokensBase()`), deploy the token triple on
Ethereum via the V4 `StoxUnifiedDeployer` at its deterministic address, with
`name` / `symbol` / `decimals` identical to the Base instance and the Ethereum
authoriser clone as the authoriser. Transfer each receipt vault's ownership to
the Ethereum Safe (matching Base, where every vault's `owner()` is the Safe).

- [ ] 20 token triples deployed; per-token config matches Base.
- [ ] **[pin PR]** Hydrate the Ethereum token table (added alongside the
      cross-chain parity pin) with the deployed addresses; register the
      per-chain entries in st0x.registry (RAI-1101).

## 8. Parity green

- [ ] The cross-chain parity suite (RAI-1097) passes with Ethereum in live state
      — core codehashes, per-token config, role parity, beacon owners — and
      stays green in scheduled CI.
