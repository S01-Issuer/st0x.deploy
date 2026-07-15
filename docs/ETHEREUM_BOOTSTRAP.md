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

## 3. Ethereum token-owner Safe (distinct per-chain address)

The Ethereum token-owner Safe is a **distinct per-chain address** — the
matched/deterministic address approach was **abandoned** (Josh, 2026-07-15).
Each chain gets its own Safe; the address is just a per-chain deploy artifact
(like the authoriser clone + token addresses), **not** a principal. The service
signer stays shared (`LibAuthoriserInvariants.GRANTEE_SERVICE_1C66`), and the
whole Safe **policy** — owner set, threshold, v1.4.1 singleton/proxy codehash,
fallback handler, no modules/guard — is the shared pin set in
`LibSafeInvariants`, which is Base's current truth.

Deploy the Safe **out-of-band** (Safe UI / custody) as a clean v1.4.1 Safe with
Base's current owner set and threshold, then pin its address. No in-repo deploy
script: we create the Safe ourselves and only add the address.

- [ ] Deploy the Ethereum token-owner Safe out-of-band: a fresh **v1.4.1** Safe
      with Base's current owner set (`LibSafeInvariants.expectedOwners()`) and
      threshold (`STOX_TOKEN_OWNER_SAFE_THRESHOLD` = 3), default
      `CompatibilityFallbackHandler`, no modules, no guard. Owner _order_ need
      not match Base — the parity check is order-insensitive.
- [ ] **[pin PR]** Hydrate `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM`
      with the deployed Safe address. `EthereumTokenOwnerSafeParityTest` is
      PENDING until this is set; once pinned it forks Ethereum and asserts the
      live Safe matches Base's shared policy in every way that matters (v1.4.1
      identity, owner SET, threshold) — and stays red into the future (scheduled
      CI) on any drift.

> The address is `address(0)` until pinned, so every per-chain consumer
> (`safeForChainId`, the parity pin, the token-authorise script) treats Ethereum
> as pending-bootstrap until the real Safe address lands.

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
